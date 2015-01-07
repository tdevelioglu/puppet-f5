require 'puppet/provider/f5'

Puppet::Type.type(:f5_virtualserver).provide(:f5_virtualserver, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 irules"

  mk_resource_methods

  confine :feature => :ruby_savon
  defaultfor :feature => :ruby_savon

  def initialize(value={})
    super(value)
    @property_flush = {}
  end

  def self.wsdl
    'LocalLB.VirtualServer'
  end

  def wsdl
    self.class.wsdl
  end

  def self.instances
    instances = []

    # Getting all info from an F5 is not transactional. But we're safe as
    # long as we are the only one doing writes.
    #
    set_activefolder('/')
    transport['System.Session'].call(:set_recursive_query_state, message: { state: 'STATE_ENABLED' })

    names = arraywrap(transport[wsdl].get(:get_list))
    getmsg = { virtual_servers: { item: names } }

    addresses = []
    ports     = []
    arraywrap(transport[wsdl].get(:get_destination, getmsg)).each do |destination|
      addresses << destination[:address]
      ports << destination[:port]
    end

    descriptions                  = arraywrap(transport[wsdl].get(:get_description, getmsg)).collect do |desc|
      desc.nil? ? "" : desc
    end

    default_pools                 = arraywrap(transport[wsdl].get(:get_default_pool_name, getmsg))
    fallback_persistence_profiles = arraywrap(transport[wsdl].get(:get_fallback_persistence_profile, getmsg))

    persistence_profiles = []
    arraywrap(transport[wsdl].get(:get_persistence_profile, getmsg)).each do |profile_list|
      if !profile_list.nil?
        default_profile = profile_list.find{ |profile| profile[:default_profile] == true }
        persistence_profiles << default_profile[:profile_name]
      else
        persistence_profiles << nil
      end
    end

    profiles = []
    arraywrap(transport[wsdl].get(:get_profile, getmsg)).each do |profile_dict|
      profile_names = []
      if !profile_dict.nil?
        [profile_dict[:item]].flatten.each do |profile|
          profile_names << profile[:profile_name]
        end
      end
      profiles << profile_names
    end

    protocols = arraywrap(transport[wsdl].get(:get_protocol, getmsg))
    types     = arraywrap(transport[wsdl].get(:get_type, getmsg))
    wildmasks = arraywrap(transport[wsdl].get(:get_wildmask, getmsg))

    names.each_index do |index|
      instances << new(
        :name                         => names[index],
        :ensure                       => :present,
        :description                  => descriptions[index],
        :address                      => addresses[index],
        :default_pool                 => default_pools[index],
        :port                         => ports[index],
        :fallback_persistence_profile => fallback_persistence_profiles[index],
        :persistence_profile          => persistence_profiles[index],
        :protocol                     => protocols[index].gsub("PROTOCOL_", ""),
        :profiles                     => profiles[index],
        :type                         => types[index].gsub("RESOURCE_TYPE_", ""),
        :wildmask                     => wildmasks[index],
      )
    end

    instances
  end

  def self.prefetch(resources)
    f5_vservers = instances

    resources.keys.each do |name|
      if provider = f5_vservers.find{ |vserver| vserver.name == name }
        resources[name].provider = provider
      end
    end
  end

  # Profiles UDP/TCP/SCTP can not co-exist.
  #
  # When switching protocols we need to make sure the protocol profiles are removed.
  def self.remove_protocol_profiles(vs)
    protocol_profiles = [
      { profile_name: "/Common/sctp" },
      { profile_name: "/Common/tcp" },
      { profile_name: "/Common/udp" }
    ]

    remove_profiles = []
    arraywrap(transport[wsdl].get(:get_profile, getmsg)).each do |profile_list|
      profile_list.each do |profile|
        if !protocol_profiles.find { |prof| prof[:profile_name] == profile[:profile_name] }.nil?
          remove_profiles << { :profile_name => profile["profile_name"] }
        end
      end
    end

    message = { virtual_servers: { item: vs }, profiles: { item: remove_profiles } }
    transport[wsdl].call(:remove_profile, message: message)
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    @property_flush[:ensure]                       = :create
    @property_flush[:description]                  = resource[:description]
    @property_flush[:fallback_persistence_profile] = resource[:fallback_persistence_profile]
    @property_flush[:persistence_profile]          = resource[:persistence_profile]
  end

  def destroy
    @property_flush[:ensure] = :destroy
  end

  def description=(value)
    @property_flush[:description] = value
  end

  def address=(value)
    @property_flush[:address] = value
  end

  def default_pool=(value)
    @property_flush[:default_pool] = value
  end

  def fallback_persistence_profile=(value)
    @property_flush[:fallback_persistence_profile] = value
  end

  def persistence_profile=(value)
    @property_flush[:persistence_profile] = value
  end

  def port=(value)
    @property_flush[:port] = value
  end

  def protocol=(value)
    @property_flush[:protocol] = value
  end

  def profiles=(value)
    @property_flush[:profiles] = value
  end

  def type=(value)
    @property_flush[:type] = value
  end

  def wildmask=(value)
    @property_flush[:wildmask] = value
  end

  def flush
    partition = File.dirname(resource[:name])
    set_activefolder(partition)

    vs = { virtual_servers: { item: resource[:name] } }
    if @property_flush[:ensure] == :destroy
      transport[wsdl].call(:delete_virtual_server, message: vs)
      return
    end

    begin
      transport['System.Session'].call(:start_transaction)

      if @property_flush[:ensure] == :create
        vs_definition = {
          name: resource[:name],
          address: resource[:address],
          port: resource[:port],
          protocol: "PROTOCOL_#{resource[:protocol]}"
        }
        vs_resources = {
          type: "RESOURCE_TYPE_#{resource[:type]}",
          default_pool_name: resource[:default_pool]
        }
        vs_profiles = resource[:profiles].nil? ? [] :
          resource[:profiles].map do |profile| {
            profile_name: profile, profile_context: nil }
          end

        message = {
          definitions: { item: vs_definition },
          wildmasks:   { item: resource[:wildmask] },
          resources:   { item: vs_resources },
          profiles:    { item: { item: vs_profiles } }
        }
        transport[wsdl].call(:create, message: message)
      end

      unless @property_flush[:description].nil?
        message = vs.merge(descriptions: { item: @property_flush[:description] })
        transport[wsdl].call(:set_description, message: message)
      end

      unless @property_flush[:address].nil? && @property_flush[:port].nil?
        address = @property_flush[:address].nil? ?
          @property_hash[:address] : @property_flush[:address]

        port = @property_flush[:port].nil? ?
          @property_hash[:port] : @property_flush[:port]

        message = vs.merge(destinations: {
          item: { :address => address,:port => port }
        })
        transport[wsdl].call(:set_destination, message: message)
      end

      unless @property_flush[:default_pool].nil?
        message = vs.merge(default_pools: { item: @property_flush[:default_pool] })
        transport[wsdl].call(:set_default_pool_name, message: message)
      end

      unless @property_flush[:fallback_persistence_profile].nil?
        message = vs.merge(profile_names: {
          item: @property_flush[:fallback_persistence_profile] 
        })
        transport[wsdl].call(:set_fallback_persistence_profile, message: message)
      end

      unless @property_flush[:persistence_profile].nil?
        # Unless we're being created, OR there is no current persistence_profile
        unless @property_hash[:persistence_profile].nil? ||
          @property_hash[:persistence_profile].empty?

          profile = { profile_name:  @property_hash[:persistence_profile], default_profile: true }
          message = vs.merge(profiles: { item: profile })
          transport[wsdl].call(:remove_persistence_profile, message: message)
        end

        unless @property_flush[:persistence_profile].empty?
          profile = { profile_name:  @property_flush[:persistence_profile], default_profile: true }
          message = vs.merge(profiles: { item: profile })
          transport[wsdl].call(:add_persistence_profile, message: message)
        end
      end

      unless @property_flush[:protocol].nil?
        self.class.remove_protocol_profiles(resource[:name])

        message = vs.merge(protocols: { item: "PROTOCOL_#{@property_flush[:protocol]}" })
        transport[wsdl].call(:set_protocol, message: message)
      end

      unless @property_flush[:profiles].nil?
        profiles = @property_hash[:profiles].map{ |p| { profile_name: p, profile_context: nil } }
        message  = vs.merge(profiles: { item: { item: profiles } })
        transport[wsdl].call(:remove_profile, message: message)

        profiles = @property_flush[:profiles].map{ |p| { profile_name: p, profile_context: nil } }
        message  = vs.merge(profiles: { item: { item: profiles } })
        transport[wsdl].call(:add_profile, message: message)
      end

      unless @property_flush[:type].nil?
        message = vs.merge(types: { item: "RESOURCE_TYPE_#{@property_flush[:type]}" })
        transport[wsdl].call(:set_type, message: message)
      end

      unless @property_flush[:wildmask].nil?
        message = vs.merge(wildmasks: { item: @property_flush[:wildmask] })
        transport[wsdl].call(:set_wildmask, message: message)
      end

      transport['System.Session'].call(:submit_transaction)
    rescue Exception
      begin
        transport['System.Session'].call(:rollback_transaction)
      rescue Exception => e
        if !e.message.include?("No transaction is open to roll back")
          raise
        end
      end
      raise
    end

    @property_hash = resource.to_hash
  end
end

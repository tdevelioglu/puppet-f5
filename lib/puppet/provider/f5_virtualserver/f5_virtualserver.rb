require 'puppet/provider/f5'

Puppet::Type.type(:f5_virtualserver).provide(:f5_virtualserver, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 irules"

  mk_resource_methods

  confine :feature => :posix
  confine :feature => :ruby_f5_icontrol
  defaultfor :feature => :posix

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
    Puppet.debug("Puppet::Device::F5: setting active partition to: /")
    transport['System.Session'].set_active_folder('/')
    transport['System.Session'].set_recursive_query_state('STATE_ENABLED')

    names = transport[wsdl].get_list

    addresses = []
    ports = []
    transport[wsdl].get_destination(names).each do |destination|
      addresses << destination["address"]
      ports << destination["port"]
    end

    descriptions                  = transport[wsdl].get_description(names)
    default_pools                 = transport[wsdl].get_default_pool_name(names)
    fallback_persistence_profiles = transport[wsdl].get_fallback_persistence_profile(names)

    persistence_profiles = []
    transport[wsdl].get_persistence_profile(names).each do |profile_list|
      default_profile = profile_list.find{ |profile| profile["default_profile"] == true }
      if !default_profile.nil?
        persistence_profiles << default_profile["profile_name"]
      else
        persistence_profiles << ""
      end
    end

    profiles = []
    transport[wsdl].get_profile(names).each do |profile_list|
      profile_names = []
      profile_list.each do |profile|
        profile_names << profile["profile_name"]
      end
      profiles << profile_names
    end

    protocols = transport[wsdl].get_protocol(names)
    types     = transport[wsdl].get_type(names)
    wildmasks = transport[wsdl].get_wildmask(names)

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

    Puppet.debug("Puppet::Device::F5: setting active partition to: #{partition}")
    transport['System.Session'].set_active_folder(partition)

    if @property_flush[:ensure] == :destroy
      transport[wsdl].delete_virtual_server([resource[:name]])
      return
    end

    begin
      begin
        transport['System.Session'].rollback_transaction
      rescue Exception => e
      end

      transport['System.Session'].start_transaction

      if @property_flush[:ensure] == :create
        transport[wsdl].create(
          [{ :name     => resource[:name],
             :address  => resource[:address],
             :port     => resource[:port],
             :protocol => "PROTOCOL_#{resource[:protocol]}"
          }],
          [resource[:wildmask]],
          [{ :type => "RESOURCE_TYPE_#{resource[:type]}", :default_pool_name => resource[:default_pool] }],
          [resource[:profiles].map{ |profile| {:profile_name => profile} } |
           [{ :profile_name => "/Common/tcp" }]]
        )
      end

      unless @property_flush[:description].nil?
        transport[wsdl].set_description([resource[:name]],[@property_flush[:description]])
      end
    
      unless @property_flush[:address].nil? && @property_flush[:port].nil?
        address = @property_flush[:address].nil? ?
          @property_hash[:address] : @property_flush[:address]

        port = @property_flush[:port].nil? ?
          @property_hash[:port] : @property_flush[:port]

        transport[wsdl].set_destination([resource[:name]],
         [{ :address => address, :port => port }])
      end
    
      unless @property_flush[:default_pool].nil?
        transport[wsdl].set_default_pool_name([resource[:name]], [@property_flush[:default_pool]])
      end
    
      unless @property_flush[:fallback_persistence_profile].nil?
        transport[wsdl].set_fallback_persistence_profile([resource[:name]],
         [@property_flush[:fallback_persistence_profile]])
      end
    
      unless @property_flush[:persistence_profile].nil?
        # Unless we're being created, OR there is no current persistence_profile
        unless @property_hash[:persistence_profile].nil? ||
          @property_hash[:persistence_profile].empty?
          transport[wsdl].remove_persistence_profile([resource[:name]],
            [[{ :profile_name => @property_hash[:persistence_profile], :default_profile => true }]])
        end

        unless @property_flush[:persistence_profile].empty?
          transport[wsdl].add_persistence_profile([resource[:name]],
            [[{ :profile_name  => @property_flush[:persistence_profile], :default_profile => true }]])
        end
      end
    
      unless @property_flush[:protocol].nil?
        self.class.remove_protocol_profiles(resource[:name])
        
        transport[wsdl].set_protocol([resource[:name]], ["PROTOCOL_#{@property_flush[:protocol]}"])
      end
    
      unless @property_flush[:profiles].nil?
        transport[wsdl].remove_profile([resource[:name]],
         [@property_hash[:profiles].map{ |profile| { :profile_name => profile } }])

        transport[wsdl].add_profile([resource[:name]],
         [@property_flush[:profiles].map{ |profile| { :profile_name => profile } }]) 
      end
    
      unless @property_flush[:type].nil?
        transport[wsdl].set_type([resource[:name]], ["RESOURCE_TYPE_#{@property_flush[:type]}"])
      end
    
      unless @property_flush[:wildmask].nil?
        transport[wsdl].set_wildmask([resource[:name]], [@property_flush[:wildmask]])
      end

      transport['System.Session'].submit_transaction
    rescue Exception => e
      transport['System.Session'].rollback_transaction
      raise e
    end

  end

  # Another F5 API bug
  # Profiles UDP/TCP/SCTP can not co-exist in clientside, nor serverside.
  #
  # When switching protocols we need to make sure the protocol profiles are removed
  def self.remove_protocol_profiles(vs)
    protocol_profiles = [
      { :profile_name => "/Common/sctp" },
      { :profile_name => "/Common/tcp" },
      { :profile_name => "/Common/udp" }
    ]

    remove_profiles = []
    transport[wsdl].get_profile([vs]).each do |profile_list|
      profile_list.each do |profile|
        if !protocol_profiles.find { |prof| prof[:profile_name] == profile["profile_name"] }.nil?
          remove_profiles << { :profile_name => profile["profile_name"] }
        end
      end
    end

    transport[wsdl].remove_profile([vs],[remove_profiles])
  end
end

require 'puppet/provider/f5'

Puppet::Type.type(:f5_virtualserver).provide(:f5_virtualserver, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 irules"

  # TODO: Move into Puppet::Provider::F5
  def self.mk_resource_methods
    [resource_type.validproperties, resource_type.parameters].flatten.each do |attr|
      attr = attr.intern
      next if attr == :name
      define_method(attr) do
        if @property_hash[attr].nil?
          :absent
        else
          @property_hash[attr]
        end
      end

      define_method(attr.to_s + "=") do |val|
        @property_flush[attr] = val
      end
    end

    define_method(:exists?) do
      @property_hash[:ensure] == :present
    end

    properties = resource_type.validproperties
    define_method(:create) do 
      @property_flush[:ensure] = :create
      properties.each do |x|
        next if x == :ensure
        @property_flush[x] = resource["atcreate_#{x}".to_sym] || resource[x]
      end
    end

    define_method(:destroy) do
      @property_flush[:ensure] = :destroy
    end
  end

  mk_resource_methods

  confine :feature => :ruby_savon
  defaultfor :feature => :ruby_savon

  def self.protocol_profiles
    ["/Common/tcp", "/Common/udp"]
  end

  def protocol_profiles
    self.class.protocol_profiles
  end

  def self.profile_properties
    [:ftp_profile, :http_profile, :protocol_profile_client,
     :protocol_profile_server, :responseadapt_profile, :requestadapt_profile,
     :sip_profile, :ssl_profiles_client, :ssl_profiles_server, :stream_profile,
     :statistics_profile, :xml_profile]
  end

  def profile_properties
    self.class.profile_properties
  end

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
    set_activefolder('/')
    enable_recursive_query

    names  = arraywrap(transport[wsdl].get(:get_list))
    @getmsg = { virtual_servers: { item: names } }
    def self.soapget(method)
      arraywrap(transport[wsdl].get(method, @getmsg))
    end

    ##############################
    # Addresses / Ports
    ##############################
    addresses = []
    ports     = []
    soapget(:get_destination).each do |dest|
      addresses << dest[:address]
      ports     << dest[:port]
    end

    ##############################
    # Descriptions
    ##############################
    descriptions =
      soapget(:get_description).collect { |desc| desc.nil? ? "" : desc }

    ##############################
    # Default pools
    ##############################
    default_pools = soapget(:get_default_pool_name)

    ##############################
    # Authentication profiles
    ##############################
    authprofileslistlist =
      soapget(:get_authentication_profile).collect do |profiles|
        arraywrap(profiles[:item]) if !profiles.nil?
      end
    authprofiles = Array.new(authprofileslistlist.size) do |idx|
      if !authprofileslistlist[idx].nil?
        authprofileslistlist[idx].collect { |prof| prof[:profile_name] }
      end
    end

    ##############################
    # Persistence profiles
    ##############################
    fallback_persistence_profiles = soapget(:get_fallback_persistence_profile)

    persistence_profiles = []
    soapget(:get_persistence_profile).each do |profile_list|
      if !profile_list.nil?
        default_profile = profile_list.find{ |profile| profile[:default_profile] == true }
        persistence_profiles << default_profile[:profile_name]
      else
        persistence_profiles << nil
      end
    end

    ##############################
    # Profiles
    ##############################
    profileslistlist =
      soapget(:get_profile).collect { |profiles| arraywrap(profiles[:item]) }

    ftpprofiles             = Array.new(profileslistlist.size, nil)
    httpprofiles            = Array.new(profileslistlist.size, nil)
    protocolprofiles_client = Array.new(profileslistlist.size, nil)
    protocolprofiles_server = Array.new(profileslistlist.size, nil)
    responseadaptprofiles   = Array.new(profileslistlist.size, nil)
    requestadaptprofiles    = Array.new(profileslistlist.size, nil)
    sipprofiles             = Array.new(profileslistlist.size, nil)
    sslprofiles_client      = Array.new(profileslistlist.size) { [] }
    sslprofiles_server      = Array.new(profileslistlist.size) { [] }
    statisticsprofiles      = Array.new(profileslistlist.size, nil)
    streamprofiles          = Array.new(profileslistlist.size, nil)
    xmlprofiles             = Array.new(profileslistlist.size, nil)
    profileslistlist.each_with_index do |profileslist, idx|
      profileslist.each do |profile|
        if ['PROFILE_TYPE_TCP',
            'PROFILE_TYPE_UDP'].include?(profile[:profile_type])
          if profile[:profile_context] == 'PROFILE_CONTEXT_TYPE_ALL'
            protocolprofiles_client[idx] = profile[:profile_name]
            protocolprofiles_server[idx] = profile[:profile_name]
          elsif profile[:profile_context] == 'PROFILE_CONTEXT_TYPE_CLIENT'
            protocolprofiles_client[idx] = profile[:profile_name]
          elsif profile[:profile_context] == 'PROFILE_CONTEXT_TYPE_SERVER'
            protocolprofiles_server[idx] = profile[:profile_name]
          end
        elsif profile[:profile_type] == 'PROFILE_TYPE_CLIENT_SSL'
          sslprofiles_client[idx] << profile[:profile_name]
        elsif profile[:profile_type] == 'PROFILE_TYPE_SERVER_SSL'
          sslprofiles_server[idx] << profile[:profile_name]
        elsif profile[:profile_type] == 'PROFILE_TYPE_HTTP'
          httpprofiles[idx] = profile[:profile_name]
        elsif profile[:profile_type] == 'PROFILE_TYPE_FTP'
          ftpprofiles[idx] = profile[:profile_name]
        elsif profile[:profile_type] == 'PROFILE_TYPE_STREAM'
          streamprofile[idx] = profile[:profile_name]
        elsif profile[:profile_type] == 'PROFILE_TYPE_XML'
          xmlprofiles[idx] = profile[:profile_name]
        elsif profile[:profile_type] == 'PROFILE_TYPE_SIPP'
          sipprofiles[idx] = profile[:profile_name]
        elsif profile[:profile_type] == 'PROFILE_TYPE_STATISTICS'
          statisticsprofiles[idx] = profile[:profile_name]
        elsif profile[:profile_type] == 'PROFILE_TYPE_RESPONSEADAPT'
          responseadaptprofiles[idx] = profile[:profile_name]
        elsif profile[:profile_type] == 'PROFILE_TYPE_REQUESTADAPT'
          requestadaptprofiles[idx] = profile[:profile_name]
        end
      end
    end

    ##############################
    # Protocols/Types/Wildmasks
    ##############################
    protocols =
      soapget(:get_protocol).collect { |prot| prot.gsub("PROTOCOL_", "") }
    types =
      soapget(:get_type).collect { |type| type.gsub("RESOURCE_TYPE_", "") }
    wildmasks = soapget(:get_wildmask)

    ##############################
    # Instantiate providers
    ##############################
    names.each_index do |idx|
      instances << new(
        :address                      => addresses[idx],
        :auth_profiles                => authprofiles[idx],
        :default_pool                 => default_pools[idx],
        :description                  => descriptions[idx],
        :ensure                       => :present,
        :fallback_persistence_profile => fallback_persistence_profiles[idx],
        :ftp_profile                  => ftpprofiles[idx],
        :http_profile                 => httpprofiles[idx],
        :name                         => names[idx],
        :persistence_profile          => persistence_profiles[idx],
        :port                         => ports[idx],
        :protocol                     => protocols[idx],
        :protocol_profile_client      => protocolprofiles_client[idx],
        :protocol_profile_server      => protocolprofiles_server[idx],
        :responseadapt_profile        => responseadaptprofiles[idx],
        :requestadapt_profile         => requestadaptprofiles[idx],
        :sip_profile                  => sipprofiles[idx],
        :ssl_profiles_client          => sslprofiles_client[idx],
        :ssl_profiles_server          => sslprofiles_server[idx],
        :statistics_profile           => statisticsprofiles[idx],
        :stream_profile               => streamprofiles[idx],
        :type                         => types[idx],
        :wildmask                     => wildmasks[idx],
        :xml_profile                  => xmlprofiles[idx],
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

  # Return a list of api profile object hashes that should be "flushed".
  def all_profiles(property_hash)
    profiles = []

    client = property_hash[:protocol_profile_client] || property_hash[:protocol_profile_server]
    server = property_hash[:protocol_profile_server] || property_hash[:protocol_profile_client]
    if !client.nil?
      if client == server
        profiles << { :profile_name => client,
                      :profile_type => nil,
                      :profile_context => "PROFILE_CONTEXT_TYPE_ALL" }
      else
        profiles << { :profile_name => client,
                      :profile_type => nil,
                      :profile_context => "PROFILE_CONTEXT_TYPE_CLIENT" }
        profiles << { :profile_name => server,
                      :profile_type => nil,
                      :profile_context => "PROFILE_CONTEXT_TYPE_SERVER" }
      end
    end

    (profile_properties - [:protocol_profile_client,
                           :protocol_profile_server]).each do |propertyname|
      property_hash[propertyname].nil? && next
      type, context = /^([^_]+)_PROFILES?_?([^_]+)?$/.match(
        propertyname.upcase).captures
      context = context || "ALL"

      type = 'SIPP' if type == 'SIP'
      arraywrap(property_hash[propertyname]).each do |profile|
        profiles << { profile_name: profile,
                      profile_type: "PROFILE_TYPE_#{context}_#{type}",
                      profile_context: "PROFILE_CONTEXT_TYPE_#{context}" }
      end
    end
    profiles
  end

  # Check if there are any profiles that need to be flushed.
  def flush_profiles?
    profile_properties.any? { |prop| !@property_flush[prop].nil? }
  end

  ###########################################################################
  # Flush
  ###########################################################################
  def flush
    @vserver = { virtual_servers: { item: resource[:name] } }
    set_activefolder('/Common')

    if @property_flush[:ensure] == :destroy
      ##############################
      # Destroy
      ##############################
      soapcall(:delete_virtual_server)
      return
    end

    begin
      start_transaction
      ##############################
      # Create
      ##############################
      if @property_flush[:ensure] == :create
        vs_definition = {
          name: resource[:name],
          address: @property_flush[:address],
          port: @property_flush[:port],
          protocol: "PROTOCOL_#{@property_flush[:protocol]}"
        }

        vs_resources = {
          type: "RESOURCE_TYPE_#{@property_flush[:type]}",
          default_pool_name: @property_flush[:default_pool]
        }

        # Pass empty hash if no profiles are declared to keep
        # API happy. Saves us from having to determine a default.
        if @property_flush[:profiles].nil? || @property_flush[:profiles].empty?
          vs_profiles = {}
        else
          vs_profiles = { item: all_profiles(@property_flush) }
        end
        message = {
          definitions: { item: vs_definition },
          wildmasks:   { item: @property_flush[:wildmask] },
          resources:   { item: vs_resources },
          profiles:    { item: vs_profiles }
        }
        transport[wsdl].call(:create, message: message)
      ##############################
      # Modify
      ##############################
      else
        # Destination (address/port)
        if !@property_flush[:address].nil? || !@property_flush[:port].nil?
          address = @property_flush[:address] || @property_hash[:address]
          port = @property_flush[:port] || @property_hash[:port]

          soapcall(:set_destination, :destinations,
                   { address: address, port: port })
        end
        # Default_pool
        if !@property_flush[:default_pool].nil?
          soapcall(:set_default_pool_name, :default_pools,
                   @property_flush[:default_pool])
        end
        # Profiles
        if flush_profiles?
         soapcall(:remove_all_profiles)
         soapcall(:add_profile, :profiles, all_profiles(resource.to_hash), true)
        end
        # Protocol
        if !@property_flush[:protocol].nil?
          soapcall(:set_protocol, :protocols, "PROTOCOL_#{@property_flush[:protocol]}")
        end
        # Type
        if !@property_flush[:type].nil?
          soapcall(:set_type, :types, "RESOURCE_TYPE_#{@property_flush[:type]}")
        end
        # Wildmask
        if !@property_flush[:wildmask].nil?
          soapcall(:set_wildmask, :wildmasks, @property_flush[:wildmask])
        end
      end
      ##############################
      # Create/Modify
      ##############################
      # Description
      if !@property_flush[:description].nil?
        soapcall(:set_description, :descriptions, @property_flush[:description])
      end
      # Fallback persistence profile
      if !@property_flush[:fallback_persistence_profile].nil?
        soapcall(:set_fallback_persistence_profile, :profile_names,
                 @property_flush[:fallback_persistence_profile])
      end
      # Persistence profile
      if !@property_flush[:persistence_profile].nil?
        profile_hash = {
          profile_name: @property_flush[:persistence_profile],
          default_profile: true
        }
        soapcall(:remove_all_persistence_profiles)
        soapcall(:add_persistence_profile, :profiles,  profile_hash, true)
      end
      submit_transaction
    rescue Exception
      begin
        rollback_transaction
      rescue Exception => e
        if !e.message.include?("No transaction is open to roll back")
          raise
        end
      end
      raise
    end
    @property_hash = resource.to_hash
  end

  ###########################################################################
  # Soap caller
  ###########################################################################
  def soapcall(method, key=nil, value=nil, nest=false)
    soapitem = nest ? { item: { item: value } } : { item:  value }

    message = key.nil? ?  @vserver : @vserver.merge(key => soapitem)
    transport[wsdl].call(method, message: message)
  end
end

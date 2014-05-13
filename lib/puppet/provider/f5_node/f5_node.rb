require 'puppet/provider/f5'

Puppet::Type.type(:f5_node).provide(:f5_node, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 node"

  mk_resource_methods

  confine :feature => :posix
  confine :feature => :ruby_f5_icontrol
  defaultfor :feature => :posix

  def initialize(value={})
    super(value)
    @property_flush = {}
  end

  def self.wsdl
    'LocalLB.NodeAddressV2'
  end

  def wsdl
    self.class.wsdl
  end

  # The F5 api is confusing when it comes to getting and setting the
  # session_enabled_state, session_status or whatever it's now called. 
  #
  # Corresponding getter and setter methods are inconsistent, so we're using:
  #
  # get_session_status: (SESSION_STATUS_ENABLED, SESSION_STATUS_DISABLED,
  # SESSION_STATUS_FORCED_OFFLINE) and
  #
  # set_session_enabled_state: (STATE_ENABLED, STATE_DISABLED)
  #
  # to set what's the 'state' button in the UI and hope for the best.
  #
  def self.session_status_to_property(status)
    /(ENABLED|DISABLED)/.match(status)[0]
  end

  def self.property_to_session_enabled_state(property)
    'STATE_' + property
  end

  def self.monitor_rule_to_property(monitor_rule)
    if monitor_rule['monitor_templates'] == ["/Common/none"]
      ['none']
    else
      monitor_rule['monitor_templates']
    end
  end

  def self.property_to_monitor_rule(property)
    quorum = 0 # when is this not 0 ?
    type =
      if property == ["none"]
        "MONITOR_RULE_TYPE_NONE"
      elsif property.length == 1
        "MONITOR_RULE_TYPE_SINGLE"
      else
        "MONITOR_RULE_TYPE_AND_LIST"
      end

    { "monitor_templates" => property, "quorum" => quorum, "type" => type }
  end

  def self.instances
    # Getting all node info from an F5 is not transactional. But we're safe as
    # long as we are the only one doing writes.
    #
    Puppet.debug("Puppet::Device::F5: setting active partition to: /")

    transport['System.Session'].set_active_folder('/')
    transport['System.Session'].set_recursive_query_state('STATE_ENABLED')

    names             = transport[wsdl].get_list
    connection_limits = transport[wsdl].get_connection_limit(names)
    descriptions      = transport[wsdl].get_description(names)
    dynamic_ratios    = transport[wsdl].get_dynamic_ratio_v2(names)
    health_monitors   = transport[wsdl].get_monitor_rule(names)
    ipaddresses       = transport[wsdl].get_address(names)
    rate_limits       = transport[wsdl].get_rate_limit(names)
    ratios            = transport[wsdl].get_ratio(names)
    session_status    = transport[wsdl].get_session_status(names)

    instances = []
    names.each_index do |x|
     instances << new( 
       :name             => names[x],
       :ensure           => :present,
       :connection_limit => connection_limits[x],
       :description      => descriptions[x],
       :dynamic_ratio    => dynamic_ratios[x],
       :ipaddress        => ipaddresses[x],
       :health_monitors  => monitor_rule_to_property(health_monitors[x]),
       :rate_limit       => rate_limits[x],
       :ratio            => ratios[x],
       :session_status   => session_status_to_property(session_status[x]),
      )
    end

    instances
  end

  def self.prefetch(resources)
    f5_nodes = instances

    resources.keys.each do |name|
      if provider = f5_nodes.find{ |node| node.name == name }
        resources[name].provider = provider
      end
    end
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    @property_flush[:ensure]          = :create
    @property_flush[:description]     = resource[:description]
    @property_flush[:dynamic_ratio]   = resource[:dynamic_ratio]
    @property_flush[:health_monitors] = resource[:health_monitors]
    @property_flush[:rate_limit]      = resource[:rate_limit]
    @property_flush[:ratio]           = resource[:ratio]
    @property_flush[:session_status]  = resource[:session_status]
  end

  def destroy
    @property_flush[:ensure] = :destroy
  end

  def connection_limit=(value)
    @property_flush[:connection_limit] = value
  end

  def description=(value)
    @property_flush[:description] = value
  end

  def dynamic_ratio=(value)
    @property_flush[:dynamic_ratio] = value
  end

  def health_monitors=(value)
    @property_flush[:health_monitors] = value
  end

  def ipaddress=(value)
    @property_flush[:ipaddress] = value
  end

  def rate_limit=(value)
    @property_flush[:rate_limit] = value
  end

  def session_status=(value)
    @property_flush[:session_status] = value
  end

  def flush
    @partition = File.dirname(resource[:name])

    transport['System.Session'].set_active_folder(@partition)

    if @property_flush[:ensure] == :destroy
      begin
        transport['System.Session'].start_transaction

        self.class.delete_poolmembers(resource[:name])
        transport[wsdl].delete_node_address([resource[:name]])

        transport['System.Session'].submit_transaction
      rescue Exception => e
        transport['System.Session'].rollback_transaction
        raise e
      end

      return
    end

    begin
      transport['System.Session'].start_transaction

      if @property_flush[:ensure] == :create
        transport[wsdl].create([resource[:name]], [resource[:ipaddress]], [resource[:connection_limit]])
      end
  
      unless @property_flush[:ipaddress].nil?
        if resource[:force]
          # Disclaimer: I don't like this bit at all.
          #
          # LocalLB.NodeAddressV2 doesn't support updating ipaddress, so we
          # delete-create the node.
          # This can potentially leave you with a deleted node!
          transport[wsdl].delete_node_address([resource[:name]])
          transport['System.Session'].submit_transaction
  
          transport['System.Session'].start_transaction
          transport[wsdl].create([resource[:name]], [@property_flush[:ipaddress]],
            [@property_hash[:connection_limit]])
  
          # Restore node state
          transport[wsdl].set_connection_limit([resource[:name]], [@property_hash[:connection_limit]])
          transport[wsdl].set_description([resource[:name]], [@property_hash[:description]])
          transport[wsdl].set_dynamic_ratio_v2([resource[:name]], [@property_hash[:dynamic_ratio]])
          transport[wsdl].set_monitor_rule([resource[:name]],
            [self.class.property_to_monitor_rule(@property_hash[:health_monitors])])
          transport[wsdl].set_rate_limit([resource[:name]], [@property_hash[:rate_limit]])
          transport[wsdl].set_ratio([resource[:name]], [@property_hash[:ratio]])
          transport[wsdl].set_session_enabled_state([resource[:name]],
            [self.class.property_to_session_enabled_state(@property_hash[:session_status])])

          transport['System.Session'].submit_transaction
          transport['System.Session'].start_transaction
        else
          Puppet.notice("Parameter ipaddress has changed but force is " +
            "#{resource[:force]}, not updating ipaddress.)")
        end
      end

      unless @property_flush[:connection_limit].nil?
        transport[wsdl].set_connection_limit([resource[:name]], [@property_flush[:connection_limit]])
      end
  
      unless @property_flush[:description].nil?
        transport[wsdl].set_description([resource[:name]], [@property_flush[:description]])
      end
    
      unless @property_flush[:dynamic_ratio].nil?
        transport[wsdl].set_dynamic_ratio_v2([resource[:name]], [@property_flush[:dynamic_ratio]])
      end
    
      unless @property_flush[:health_monitors].nil?
        transport[wsdl].set_monitor_rule([resource[:name]],
          [self.class.property_to_monitor_rule(@property_flush[:health_monitors])])
      end
  
      unless @property_flush[:rate_limit].nil?
        transport[wsdl].set_rate_limit([resource[:name]], [@property_flush[:rate_limit]])
      end
    
      unless @property_flush[:ratio].nil?
        transport[wsdl].set_ratio([resource[:name]], [@property_flush[:ratio]])
      end
    
      unless @property_flush[:session_status].nil?
        transport[wsdl].set_session_enabled_state([resource[:name]],
          [self.class.property_to_session_enabled_state(@property_flush[:session_status])])
      end
  
      transport['System.Session'].submit_transaction
    rescue Exception => e
      transport['System.Session'].rollback_transaction
      raise e
    end

    @property_hash = resource.to_hash
  end

  def self.delete_poolmembers(node)
    partition = transport['System.Session'].get_active_folder()
    recursive = transport['System.Session'].get_recursive_query_state()

    wsdl = 'LocalLB.Pool'

    if partition != '/'
      Puppet.debug("Puppet::Device::F5: setting active partition to: /")
      transport['System.Session'].set_active_folder('/')
    end

    if recursive != 'STATE_ENABLED'
      transport['System.Session'].set_recursive_query_state('STATE_ENABLED')
    end

    all_pools       = transport[wsdl].get_list()
    all_poolmembers = transport[wsdl].get_member_v2(all_pools)

    found_pools   = []
    found_members = []

    all_pools.each_with_index do |pool, index|
      poolmembers = all_poolmembers[index]

      if poolmembers.empty?
        next
      end

      found = []
      poolmembers.each do |member|
        if member["address"] == node
          found << member
        end
      end

      unless found.empty?
        found_pools << pool
        found_members << found
      end
      
    end

    transport['System.Session'].set_active_folder('/Common')
    transport[wsdl].remove_member_v2(found_pools, found_members)

    # restore system settings
    transport['System.Session'].set_active_folder(partition)
    transport['System.Session'].set_recursive_query_state(recursive)
  end

end

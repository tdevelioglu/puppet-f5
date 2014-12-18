require 'puppet/provider/f5'

Puppet::Type.type(:f5_node).provide(:f5_node, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 node"

  mk_resource_methods

  confine :feature => :ruby_savon
  defaultfor :feature => :ruby_savon

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

  def self.debug(msg)
    Puppet.debug("(F5_Node): #{msg}")
  end

  def debug(msg)
    self.class.debug(msg)
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
    if monitor_rule[:monitor_templates].nil?
      ["default"]
    elsif monitor_rule[:monitor_templates][:item] == "/Common/none"
      ["none"]
    else
      Array(monitor_rule[:monitor_templates][:item])
    end
  end

  def self.prop_to_monrule(property)
    quorum    = 0 # when is this not 0 ?
    templates = { item: property }

    if property == ["none"]
      type      = "MONITOR_RULE_TYPE_NONE"
      templates = { item: "/Common/none" }
    elsif property == ["default"]
      type      = "MONITOR_RULE_TYPE_SINGLE"
      templates = { item: [''] }
    elsif property.length == 1
      type = "MONITOR_RULE_TYPE_SINGLE"
    else
      type = "MONITOR_RULE_TYPE_AND_LIST"
    end

    { monitor_templates: templates, quorum: quorum, type: type }
  end

  def self.delete_poolmembers(node)
    partition = transport['System.Session'].get(:get_active_folder)
    recursive = transport['System.Session'].get(:get_recursive_query_state)

    wsdl = 'LocalLB.Pool'

    if partition != '/'
      debug("Puppet::Device::F5: setting active partition to: /")
      transport['System.Session'].call(:set_active_folder, message: { folder: '/' })
    end

    if recursive != 'STATE_ENABLED'
      transport['System.Session'].call(:set_recursive_query_state, message: { state: 'STATE_ENABLED' })
    end

    all_pools       = arraywrap(transport[wsdl].get(:get_list))
    all_poolmembers = arraywrap(transport[wsdl].get(:get_member_v2, { pool_names: { item: all_pools } }))

    found_pools   = []
    found_members = []
    all_pools.each_with_index do |pool, index|
      poolmembers = arraywrap(all_poolmembers[index][:item])

      if poolmembers.nil?
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

    if ! found_pools.empty?
      transport['System.Session'].call(:set_active_folder, message: { folder: '/Common' })
      transport[wsdl].call(:remove_member_v2, message: { pool_names: { item: found_pools }, members: { item: found_members } })

      # restore system settings
      transport['System.Session'].call(:set_active_folder, message: { folder: partition })
      transport['System.Session'].call(:set_recursive_query_state, message: { state: recursive })
    end
  end

  def self.instances
    # Getting all node info from an F5 is not transactional. But we're safe as
    # long as we are the only one doing writes.
    #
    debug("Puppet::Device::F5: setting active partition to: /")

    transport['System.Session'].call(:set_active_folder, message: { folder: '/' })
    transport['System.Session'].call(:set_recursive_query_state, message: { state: 'STATE_ENABLED' })

    names  = arraywrap(transport[wsdl].get(:get_list))
    getmsg = { nodes: { item: names } }

    connection_limits = arraywrap(transport[wsdl].get(:get_connection_limit, getmsg))
    descriptions      = arraywrap(transport[wsdl].get(:get_description, getmsg)).collect do |desc|
      desc.nil? ? "" : desc
    end
    dynamic_ratios    = arraywrap(transport[wsdl].get(:get_dynamic_ratio_v2, getmsg))
    health_monitors   = arraywrap(transport[wsdl].get(:get_monitor_rule, getmsg))
    ipaddresses       = arraywrap(transport[wsdl].get(:get_address, getmsg))
    rate_limits       = arraywrap(transport[wsdl].get(:get_rate_limit, getmsg))
    ratios            = arraywrap(transport[wsdl].get(:get_ratio, getmsg))
    session_status    = arraywrap(transport[wsdl].get(:get_session_status, getmsg))

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

    transport['System.Session'].call(:set_active_folder, message: { folder: @partition })
    node = { nodes: { item: resource[:name] } }

    if @property_flush[:ensure] == :destroy
      begin
        transport['System.Session'].call(:start_transaction)

        self.class.delete_poolmembers(resource[:name])
        transport[wsdl].call(:delete_node_address, message: node)

        transport['System.Session'].call(:submit_transaction)
      rescue Exception => e
        transport['System.Session'].call(:rollback_transaction)
        raise e
      end

      return
    end

    begin
      transport['System.Session'].call(:start_transaction)

      if @property_flush[:ensure] == :create
        message = node.merge(addresses: { item: resource[:ipaddress] },
          limits: { item: resource[:connection_limit] })
        transport[wsdl].call(:create, message: message)
      end
  
      unless @property_flush[:ipaddress].nil?
        if resource[:force]
          # Disclaimer: I don't like this bit at all.
          #
          # LocalLB.NodeAddressV2 doesn't support updating ipaddress, so we
          # delete-create the node.
          # This can potentially leave you with a deleted node!
          transport[wsdl].call(:delete_node_address, message: node)
          transport['System.Session'].call(:submit_transaction)
  
          transport['System.Session'].call(:start_transaction)
          transport[wsdl].create([resource[:name]], [@property_flush[:ipaddress]],
            [@property_hash[:connection_limit]])
  
          # Restore node state
          transport[wsdl].call(:set_connection_limit, message: node.merge(limits: { item: @property_hash[:connection_limit] }))
          transport[wsdl].call(:set_description, message: node.merge( descriptions: { item: @property_hash[:description] }))
          transport[wsdl].call(:set_dynamic_ratio_v2, message: node.merge( dynamic_ratios: { item: @property_hash[:dynamic_ratio] }))
          transport[wsdl].call(:set_monitor_rule,message: node.merge(monitor_rules: { item: self.class.prop_to_monrule(@property_hash[:health_monitors]) }))
          transport[wsdl].call(:set_rate_limit, message: node.merge( limits: { item: @property_hash[:rate_limit] }))
          transport[wsdl].call(:set_ratio, message: node.merge(ratios: { item: @property_hash[:ratio] }))
          transport[wsdl].call(:set_session_enabled_state, message: node.merge(states: { item: self.class.property_to_session_enabled_state(@property_hash[:session_status]) }))

          transport['System.Session'].call(:submit_transaction)
          transport['System.Session'].call(:start_transaction)
        else
          Puppet.notice("Parameter ipaddress has changed but force is " +
            "#{resource[:force]}, not updating ipaddress.)")
        end
      end

      unless @property_flush[:connection_limit].nil?
        message = node.merge(limits: { item: @property_flush[:connection_limit] })
        transport[wsdl].call(:set_connection_limit, message: message)
      end
  
      unless @property_flush[:description].nil?
        message = node.merge(descriptions: { item: @property_flush[:description] })
        transport[wsdl].call(:set_description, message: message)
      end
    
      unless @property_flush[:dynamic_ratio].nil?
        message = node.merge(dynamic_ratios: { item: @property_flush[:dynamic_ratio] })
        transport[wsdl].call(:set_dynamic_ratio_v2, message: message)
      end
    
      unless @property_flush[:health_monitors].nil?
        message = node.merge( monitor_rules: { item: self.class.prop_to_monrule(@property_flush[:health_monitors]) })
        transport[wsdl].call(:set_monitor_rule, message: message)
      end
  
      unless @property_flush[:rate_limit].nil?
        message = node.merge(limits: { item: @property_flush[:rate_limit] })
        transport[wsdl].call(:set_rate_limit, message: message)
      end
    
      unless @property_flush[:ratio].nil?
        message = node.merge(ratios: { item: @property_flush[:ratio] })
        transport[wsdl].call(:set_ratio, message: message)
      end
    
      unless @property_flush[:session_status].nil?
        message = node.merge(states: { item: self.class.property_to_session_enabled_state(@property_flush[:session_status]) })
        transport[wsdl].call(:set_session_enabled_state, message: message)
      end
  
      transport['System.Session'].call(:submit_transaction)
    rescue Exception => e
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

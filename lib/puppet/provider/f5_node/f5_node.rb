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
    wsdl = 'LocalLB.Pool'

    set_activefolder('/')
    transport['System.Session'].call(:set_recursive_query_state, message: { state: 'STATE_ENABLED' })

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
      set_activefolder('/Common')
      transport[wsdl].call(:remove_member_v2, message: { pool_names: { item: found_pools }, members: { item: found_members } })

      # restore system settings
      set_activefolder(partition)
      transport['System.Session'].call(:set_recursive_query_state, message: { state: recursive })
    end
  end

  def self.instances
    # Getting all node info from an F5 is not transactional. But we're safe as
    # long as we are the only one doing writes.
    #
    set_activefolder('/')
    enable_recursive_query

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

  ###########################################################################
  # Exists/Create/Destroy
  ###########################################################################
  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    @property_flush[:ensure] = :create

    [:connection_limit, :description, :dynamic_ratio, :health_monitors,
     :rate_limit, :ratio, :session_status].each do |x|
      @property_flush[x] = resource["atcreate_#{x}".to_sym] || resource[x]
    end
  end

  def destroy
    @property_flush[:ensure] = :destroy
  end

  ###########################################################################
  # Setters
  ###########################################################################
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

  ###########################################################################
  # Flush
  ###########################################################################
  def flush
    @node = { nodes: { item: resource[:name] } }
    set_activefolder('/Common')

    if @property_flush[:ensure] == :destroy
      begin
        start_transaction
        self.class.delete_poolmembers(resource[:name])
        soapcall(:delete_node_address)
        submit_transaction
      rescue Exception => e
        begin
          rollback_transaction
        rescue Exception => e
          if !e.message.include?("No transaction is open to roll back")
            raise
          end
        end
      end

      return
    end

    begin
      start_transaction
      if @property_flush[:ensure] == :create
        message = @node.merge(addresses: { item: resource[:ipaddress] },
          limits: { item: @property_flush[:connection_limit] })
        transport[wsdl].call(:create, message: message)

        @property_flush.delete(:connection_limit)
      end
  
      if !@property_flush[:connection_limit].nil?
        soapcall(:set_connection_limit, :limits, @property_flush[:connection_limit])
      end
      if !@property_flush[:description].nil?
        soapcall(:set_description, :descriptions, @property_flush[:description])
      end
      if !@property_flush[:dynamic_ratio].nil?
        soapcall(:set_dynamic_ratio_v2, :dynamic_ratios, @property_flush[:dynamic_ratio])
      end
      if !@property_flush[:health_monitors].nil?
        soapcall(:set_monitor_rule, :monitor_rules,
                 self.class.prop_to_monrule(@property_flush[:health_monitors]))
      end
      if !@property_flush[:rate_limit].nil?
        soapcall(:set_rate_limit, :limits, @property_flush[:rate_limit])
      end
      if !@property_flush[:ratio].nil?
        soapcall(:set_ratio, :ratios, @property_flush[:ratio])
      end
      if !@property_flush[:session_status].nil?
        soapcall(:set_session_enabled_state, :states,
                 self.class.property_to_session_enabled_state(
                   @property_flush[:session_status]))
      end
      submit_transaction
    rescue Exception => e
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
  def soapcall(method, key=nil, value=nil)
    message = key.nil? ?
      @node : @node.merge(key => { item: value })
    transport[wsdl].call(method, message: message)
  end

end

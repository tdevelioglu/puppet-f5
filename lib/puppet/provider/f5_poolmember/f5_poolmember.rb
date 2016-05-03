require 'puppet/provider/f5'

Puppet::Type.type(:f5_poolmember).provide(:f5_poolmember, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 poolmembers"

  mk_resource_methods

  confine :feature => :ruby_savon
  defaultfor :feature => :ruby_savon

  def initialize(value={})
    super(value)
    @property_flush = {}
  end

  def self.wsdl
    'LocalLB.Pool'
  end

  def wsdl
    self.class.wsdl
  end

  def self.soapget_pools
    @pools ||= soapget(:get_list)
  end

  def self.soapget_names
    @names ||= soapget_listlist(
      :get_member_v2, nil, { pool_names: { item: soapget_pools } })
  end

  def self.soapget_attribute(method)
    getmsg  = { pool_names: { item: soapget_pools },
                members:    { item: soapget_names } }
    soapget(method, getmsg)
  end

  def self.instances
    return @instances if @instances

    debug("Fetching instances")
    instances = []
    set_activefolder('/')
    enable_recursive_query

    connection_limits = soapget_listlist(:get_member_connection_limit)
    descriptions      = soapget_listlist(:get_member_description)
    priority_groups   = soapget_listlist(:get_member_priority)
    rate_limits       = soapget_listlist(:get_member_rate_limit)
    ratios            = soapget_listlist(:get_member_ratio)
    session_status    = soapget_listlist(:get_member_session_status)

    soapget_names.each_with_index do |pmlist, idx1|
      pmlist.each_with_index do |pm, idx2|
        pool, node, port = soapget_pools[idx1], pm[:address], pm[:port]
        instances << new(
          :ensure           => :present,
          :name             => "#{pool}:#{node}:#{port}",
          :connection_limit => connection_limits[idx1][idx2],
          :description      => descriptions[idx1][idx2] || "",
          :priority_group   => priority_groups[idx1][idx2],
          :rate_limit       => rate_limits[idx1][idx2],
          :ratio            => ratios[idx1][idx2],
          :session_status   => session_status_to_property(session_status[idx1][idx2]),
        )
      end
    end
    @instances = instances
  end

  def self.prefetch(resources)
    poolmembers = instances

    resources.each do |name, resource|
      if provider = poolmembers.find{ |poolmember| poolmember.name == name }
        resource.provider = provider
      end
    end
  end

  ###########################################################################
  # Flush
  ###########################################################################
  def flush
    addressport = { address: resource.node, port: resource.port.to_i }
    @poolmember = {
      pool_names: { item: resource.pool },
      members:    { item: { item: addressport } }
    }
    set_activefolder('/Common')

    if @property_flush[:ensure] == :destroy
      soapcall(:remove_member_v2)
      return
    end

    begin
      start_transaction
      if @property_flush[:ensure] == :create
        soapcall(:add_member_v2)
      end
      if !@property_flush[:connection_limit].nil?
        soapcall(:set_member_connection_limit, :limits, @property_flush[:connection_limit])
      end
      if !@property_flush[:description].nil?
        soapcall(:set_member_description, :descriptions, @property_flush[:description])
      end
      if !@property_flush[:priority_group].nil?
        soapcall(:set_member_priority, :priorities, @property_flush[:priority_group])
      end
      if !@property_flush[:rate_limit].nil?
        soapcall(:set_member_rate_limit, :limits, @property_flush[:rate_limit])
      end
      if !@property_flush[:ratio].nil?
        soapcall(:set_member_ratio, :ratios, @property_flush[:ratio])
      end
      if !@property_flush[:session_status].nil?
        soapcall(:set_member_session_enabled_state, :session_states,
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
      @poolmember : @poolmember.merge(key => { item: { item: value } })
    transport[wsdl].call(method, message: message)
  end

end

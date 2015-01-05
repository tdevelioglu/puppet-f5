require 'puppet/provider/f5'

Puppet::Type.type(:f5_pool).provide(:f5_pool, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 pool"

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

  def self.instances
    # Getting all pool info from an F5 is not transactional. But we're safe as
    # long as we are the only one doing writes.
    #
    set_activefolder('/')
    transport['System.Session'].call(:set_recursive_query_state, message: { state: 'STATE_ENABLED' })

    pools  = arraywrap(transport[wsdl].get(:get_list))
    getmsg = { pool_names: { item: pools } }

    descriptions = arraywrap(transport[wsdl].get(:get_description, getmsg)).collect do |desc|
      desc.nil? ? "" : desc
    end

    lb_methods = arraywrap(transport[wsdl].get(:get_lb_method, getmsg))
    members    = arraywrap(transport[wsdl].get(:get_member_v2, getmsg)).collect do |x|
      x.nil? ? [] : arraywrap(x[:item])
    end

    health_monitors =
      arraywrap(transport[wsdl].get(:get_monitor_association, getmsg)).collect do |monitor|
        if monitor[:monitor_rule][:monitor_templates].nil?
          []
        else
          arraywrap(monitor[:monitor_rule][:monitor_templates][:item])
        end
      end

    instances = []
    pools.each_index do |index|
      instances << new( 
        :name            => pools[index],
        :ensure          => :present,
        :description     => descriptions[index],
        :lb_method       => lb_methods[index].gsub("LB_METHOD_", ""),
        :members         => members[index],
        :health_monitors => health_monitors[index],
      )
    end

    instances
  end

  def self.prefetch(resources)
    f5_pools = instances

    resources.keys.each do |name|
      if provider = f5_pools.find{ |pool| pool.name == name }
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
    @property_flush[:health_monitors] = resource[:health_monitors]
    @property_flush[:lb_method]       = resource[:lb_method].nil? ?
      'ROUND_ROBIN' : resource[:health_monitors]
    @property_flush[:members]         = resource[:members].nil? ?
      [] : resource[:members]
  end

  def destroy
    @property_flush[:ensure] = :destroy
  end

  def description=(value)
    @property_flush[:description] = value
  end

  def lb_method=(value)
    @property_flush[:lb_method] = value
  end

  def members=(value)
    @property_flush[:members] = value
  end

  def health_monitors=(value)
    @property_flush[:health_monitors] = value
  end

  def flush
    @partition = File.dirname(resource[:name])
    set_activefolder(@partition)

    pool = { pool_names: { item: resource[:name] } }
    if @property_flush[:ensure] == :destroy
      transport[wsdl].call(:delete_pool, message: pool)
      return
    end

    begin
      transport['System.Session'].call(:start_transaction)
  
      if @property_flush[:ensure] == :create
        message = pool.merge(lb_methods: { item: "LB_METHOD_#{@property_flush[:lb_method]}" },
                             members: { item: @property_flush[:members] })
        transport[wsdl].call(:create_v2, message: message)

        # Prevent further API calls.
        @property_flush.delete(:lb_method)
        @property_flush.delete(:members)
      end
  
      unless @property_flush[:lb_method].nil?
        message = pool.merge(lb_methods: { item: "LB_METHOD_#{@property_flush[:lb_method]}" })
        transport[wsdl].call(:set_lb_method, message: message)
      end
  
      unless @property_flush[:members].nil?
        members_remove = @property_hash[:members] - @property_flush[:members]
        members_add    = @property_flush[:members] - @property_hash[:members]
  
        if !members_remove.empty?
          transport[wsdl].call(:remove_member_v2, message: pool.merge(members: { item: { item: members_remove } }))
        end
        transport[wsdl].call(:add_member_v2, message: pool.merge(members: { item: { item: members_add } }))
      end
  
      unless @property_flush[:description].nil?
        message = pool.merge(descriptions: { item: @property_flush[:description] })
        transport[wsdl].call(:set_description, message: message)
      end
    
      unless @property_flush[:health_monitors].nil?
        monitor_assoc = {
          monitor_rule: {
            monitor_templates: { item: @property_flush[:health_monitors] },
            quorum: 0,
            type: 'MONITOR_RULE_TYPE_AND_LIST'
          },
          pool_name: resource[:name]
        }
        message = { monitor_associations: { item: monitor_assoc } }
        transport[wsdl].call(:set_monitor_association, message: message)
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

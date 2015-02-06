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

  def self.soapget_attribute(method)
    super(method, :pool_names)
  end

  def self.instances
    instances = []
    set_activefolder('/')
    enable_recursive_query

    descriptions = soapget_attribute(:get_description).collect do |desc|
      desc.nil? ? "" : desc
    end

    lb_methods = soapget_attribute(:get_lb_method)
    members    = soapget_attribute(:get_member_v2).collect do |x|
      x.nil? ? [] : arraywrap(x[:item])
    end

    health_monitors =
      soapget_attribute(:get_monitor_association).collect do |monitor|
        if monitor[:monitor_rule][:monitor_templates].nil?
          []
        else
          arraywrap(monitor[:monitor_rule][:monitor_templates][:item])
        end
      end

    soapget_names.each_index do |index|
      instances << new( 
        :name            => soapget_names[index],
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
    pools = instances

    resources.keys.each do |name|
      if provider = pools.find{ |pool| pool.name == name }
        resources[name].provider = provider
      end
    end
  end

  def flush
    @pool = { pool_names: { item: resource[:name] } }
    set_activefolder('/Common')

    if @property_flush[:ensure] == :destroy
      soapcall(:delete_pool)
      return
    end

    begin
      start_transaction
      ##############################
      # Create
      ##############################
      if @property_flush[:ensure] == :create
        message = @pool.merge(lb_methods: { item: "LB_METHOD_#{@property_flush[:lb_method]}" },
                             members: { item: { item: @property_flush[:members] }})
        transport[wsdl].call(:create_v2, message: message)
      else
      ##############################
      # Create/Modify
      ##############################
      # Properties that are supported in the API create method.
        if !@property_flush[:lb_method].nil?
          soapcall(:set_lb_method, :lb_methods,
                   "LB_METHOD_#{@property_flush[:lb_method]}")
        end
    
        if !@property_flush[:members].nil?
          members_remove = @property_hash[:members] - @property_flush[:members]
          members_add    = @property_flush[:members] - @property_hash[:members]
    
          if !members_remove.empty?
            soapcall(:remove_member_v2, :members, members_remove, true)
          end
          soapcall(:add_member_v2, :members, members_add, true)
        end
      end
 
      ##############################
      # Modify only
      ##############################
      # Properties that are unsupported by the API create method.
      if !@property_flush[:description].nil?
        soapcall(:set_description, :descriptions, @property_flush[:description])
      end
    
      if !@property_flush[:health_monitors].nil?
        monitor_assoc = {
          monitor_rule: {
            monitor_templates: { item: @property_flush[:health_monitors] },
            quorum: 0,
            type: 'MONITOR_RULE_TYPE_AND_LIST'
          },
          pool_name: resource[:name]
        }
        soapcall(:set_monitor_association, :monitor_associations,
                 monitor_assoc)
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
  # Soap caller (TODO: This should be moved to Provider::F5)
  ###########################################################################
  def soapcall(method, key=nil, value=nil, nest=false)
    soapitem = nest ? { item: { item: value } } : { item:  value }

    message = key.nil? ?  @pool : @pool.merge(key => soapitem)
    transport[wsdl].call(method, message: message)
  end
end

require 'puppet/provider/f5'

Puppet::Type.type(:f5_pool).provide(:f5_pool, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 pool"

  mk_resource_methods

  confine :feature => :posix
  confine :feature => :ruby_f5_icontrol
  defaultfor :feature => :posix

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
    Puppet.debug("Puppet::Device::F5: setting active partition to: /")
    transport['System.Session'].set_active_folder('/')
    transport['System.Session'].set_recursive_query_state('STATE_ENABLED')

    pools           = transport[wsdl].get_list
    descriptions    = transport[wsdl].get_description(pools)
    lb_methods      = transport[wsdl].get_lb_method(pools)

    # F5 icontrol returns <SOAP::Mapping::Object's instead of
    # ruby hashes making it difficult to compare with the puppet resource data.
    #
    # We iterate through all the SOAP objects and collect everything again.
    members = []
    transport[wsdl].get_member_v2(pools).each do |members_list|
      members_collected = []
      members_list.each do |member|
        members_collected << {'address' => member['address'], 'port' => member['port'] }
      end
      members << members_collected
    end

    health_monitorss =
      transport[wsdl].get_monitor_association(pools).collect do |monitor|
        monitor['monitor_rule']['monitor_templates']
      end

    instances = []
    pools.each_index do |index|
      instances << new( 
        :name            => pools[index],
        :ensure          => :present,
        :description     => descriptions[index],
        :lb_method       => lb_methods[index].gsub("LB_METHOD_", ""),
        :members         => members[index],
        :health_monitors => health_monitorss[index],
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
    transport['System.Session'].set_active_folder(@partition)

    if @property_flush[:ensure] == :destroy
      transport[wsdl].delete_pool([resource[:name]])
      return
    end

    transport['System.Session'].start_transaction

    if @property_flush[:ensure] == :create
        transport[wsdl].create_v2([resource[:name]], ["LB_METHOD_#{@resource[:lb_method]}"], [@resource[:members]])
    end

    unless @property_flush[:lb_method].nil?
      transport[wsdl].set_lb_method([resource[:name]], [@property_flush[:lb_method]])
    end

    unless @property_flush[:members].nil?
      transport[wsdl].remove_member_v2([resource[:name]], [@property_hash[:members] - @property_flush[:members]])

      transport[wsdl].add_member_v2([resource[:name]], [@property_flush[:members] - @property_hash[:members]])
    end

    unless @property_flush[:description].nil?
      transport[wsdl].set_description([resource[:name]], [@property_flush[:description]])
    end
  
    unless @property_flush[:health_monitors].nil?
      monitor_assoc = {
        'monitor_rule' => {
          'monitor_templates' => @property_flush[:health_monitors],
          'quorum'            => 0,
          'type'              => 'MONITOR_RULE_TYPE_AND_LIST'
        },
        'pool_name'    => resource[:name]
      }
      transport[wsdl].set_monitor_association([monitor_assoc])
    end

    transport['System.Session'].submit_transaction

    @property_hash = resource.to_hash
  end

end

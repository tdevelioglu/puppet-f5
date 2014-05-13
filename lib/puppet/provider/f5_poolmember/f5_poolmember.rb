require 'puppet/provider/f5'

Puppet::Type.type(:f5_poolmember).provide(:f5_poolmember, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 poolmembers"

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
    # Getting all poolmember info from an F5 is not transactional. But we're safe as
    # long as we are the only one doing writes.
    #
    Puppet.debug("Puppet::Device::F5: setting active partition to: /")
    transport['System.Session'].set_active_folder('/')
    transport['System.Session'].set_recursive_query_state('STATE_ENABLED')

    pools           = transport[wsdl].get_list
    all_poolmembers = transport[wsdl].get_member_v2(pools)

    # Th F5 api  does not handle empty lists in sequences properly (it skips them and ends up
    # matching the wrong list with the wrong pool).
    instances = []
    pools.each_with_index do |pool, index|
      if all_poolmembers[index].empty?
        next
      end

      poolmembers = all_poolmembers[index]
      connection_limits = transport[wsdl].get_member_connection_limit([pool],
        [poolmembers])[0]

      descriptions = transport[wsdl].get_member_description([pool],
        [poolmembers])[0]

      priority_groups = transport[wsdl].get_member_priority([pool],
        [poolmembers])[0]

      rate_limits = transport[wsdl].get_member_rate_limit([pool],
        [poolmembers])[0]

      ratios = transport[wsdl].get_member_ratio([pool],
        [poolmembers])[0]

      poolmembers.each_with_index do |member, indexx|
        instances << new( 
          :name             => member['address'],
          :pool             => pool,
          :port             => member['port'],
          :ensure           => :present,
          :connection_limit => connection_limits[indexx],
          :description      => descriptions[indexx],
          :priority_group   => priority_groups[indexx],
          :rate_limit       => rate_limits[indexx],
          :ratio            => ratios[indexx],
        )
      end
    end

    instances
  end

  def self.prefetch(resources)
    f5_poolmembers = instances

    resources.keys.each do |name|
      if provider = f5_poolmembers.find{ |poolmember| poolmember.name == name }
        resources[name].provider = provider
      end
    end
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    @property_flush[:ensure]           = :create
    @property_flush[:connection_limit] = resource[:connection_limit]
    @property_flush[:description]      = resource[:description]
    @property_flush[:priority_group]   = resource[:priority_group]
    @property_flush[:rate_limit]       = resource[:rate_limit]
    @property_flush[:ratio]            = resource[:ratio]
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

  def priority_group=(value)
    @property_flush[:priority_group] = value
  end

  def rate_limit=(value)
    @property_flush[:rate_limit] = value
  end

  def ratio=(value)
    @property_flush[:ratio] = value
  end

  def flush
    partition   = File.dirname(resource[:name])
    addressport = { "address" => resource[:name], "port" => resource[:port] }

    Puppet.debug("Puppet::Device::F5: setting active partition to: #{partition}")
    transport['System.Session'].set_active_folder(partition)

    if @property_flush[:ensure] == :destroy
      transport[wsdl].remove_member_v2([resource[:pool]], [[addressport]])
      return
    end

    begin
      transport['System.Session'].start_transaction

      if @property_flush[:ensure] == :create
        transport[wsdl].add_member_v2([resource[:pool]], [[addressport]])
      end

      unless @property_flush[:connection_limit].nil?
        transport[wsdl].set_member_connection_limit([resource[:pool]], [[addressport]],
          [[@property_flush[:connection_limit]]])
      end
  
      unless @property_flush[:description].nil?
        transport[wsdl].set_member_description([resource[:pool]], [[addressport]],
          [[@property_flush[:description]]])
      end

      unless @property_flush[:priority_group].nil?
        transport[wsdl].set_member_priority([resource[:pool]], [[addressport]],
          [[@property_flush[:priority_group]]])
      end

      unless @property_flush[:rate_limit].nil?
        transport[wsdl].set_member_rate_limit([resource[:pool]], [[addressport]],
          [[@property_flush[:rate_limit]]])
      end
  
      unless @property_flush[:ratio].nil?
        transport[wsdl].set_member_ratio([resource[:pool]], [[addressport]], [[@property_flush[:ratio]]])
      end

      transport['System.Session'].submit_transaction
    rescue Exception => e
      raise e
      transport['System.Session'].rollback_transaction
    end

  end

end

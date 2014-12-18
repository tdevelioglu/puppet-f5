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

  def self.debug(msg)
    Puppet.debug("(F5_Poolmember): #{msg}")
  end

  def debug(msg)
    self.class.debug(msg)
  end

  def self.instances
    instances = []
    # Getting all poolmember info from an F5 is not transactional. But we're safe as
    # long as we are the only one doing writes.
    #
    debug("Puppet::Device::F5: setting active partition to: /")
    transport['System.Session'].call(:set_active_folder, message: { folder: '/' })
    transport['System.Session'].call(:set_recursive_query_state, message: { state: 'STATE_ENABLED' })

    pools   = transport[wsdl].get(:get_list)
    members = transport[wsdl].get(:get_member_v2, { pool_names: { item: pools } })
    getmsg  = { pool_names: { item: pools }, members: { item: members } }

    connection_limits = arraywrap(transport[wsdl].get(:get_member_connection_limit, getmsg))
    descriptions      = arraywrap(transport[wsdl].get(:get_member_description, getmsg))
    priority_groups   = arraywrap(transport[wsdl].get(:get_member_priority, getmsg))
    rate_limits       = arraywrap(transport[wsdl].get(:get_member_rate_limit, getmsg))
    ratios            = arraywrap(transport[wsdl].get(:get_member_ratio, getmsg))

    members.each_with_index do |dict, idx1|
      dict.nil? ? next : pms = arraywrap(dict[:item])
      pms.each_with_index do |pm, idx2|
        instances << new(
          :ensure           => :present,
          :name             => pm[:address],
          :pool             => pools[idx1],
          :port             => pm[:port],
          :connection_limit => arraywrap(connection_limits[idx1][:item])[idx2],
          :description      => arraywrap(descriptions[idx1][:item])[idx2].nil? ?
            "" : arraywrap(descriptions[idx1][:item])[idx2],
          :priority_group   => arraywrap(priority_groups[idx1][:item])[idx2],
          :rate_limit       => arraywrap(rate_limits[idx1][:item])[idx2],
          :ratio            => arraywrap(ratios[idx1][:item])[idx2],
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
    addressport = { address: resource[:name], port: resource[:port] }
    poolmember  = { pool_names: { item: resource[:pool] }, members: { item: { item: addressport } } }

    debug("Puppet::Device::F5: setting active partition to: #{partition}")
    transport['System.Session'].call(:set_active_folder, message: { folder: partition })

    if @property_flush[:ensure] == :destroy
      transport[wsdl].call(:remove_member_v2, message: poolmember)
      return
    end

    begin
      transport['System.Session'].call(:start_transaction)

      if @property_flush[:ensure] == :create
        transport[wsdl].call(:add_member_v2, message: poolmember)
      end

      unless @property_flush[:connection_limit].nil?
        message = poolmember.merge(limits: { item: { item: @property_flush[:connection_limit] } })
        transport[wsdl].call(:set_member_connection_limit, message: message)
      end
  
      unless @property_flush[:description].nil?
        message = poolmember.merge(descriptions: { item: { item: @property_flush[:description] } })
        transport[wsdl].call(:set_member_description, message: message)
      end

      unless @property_flush[:priority_group].nil?
        message = poolmember.merge(priorities: { item: { item:  @property_flush[:priority_group] } })
        transport[wsdl].call(:set_member_priority, message: message)
      end

      unless @property_flush[:rate_limit].nil?
        message = poolmember.merge(limits: { item: { item: @property_flush[:rate_limit] } })
        transport[wsdl].call(:set_member_rate_limit, message: message)
      end
  
      unless @property_flush[:ratio].nil?
        message = poolmember.merge(ratios: { item: { item: @property_flush[:ratio] } })
        transport[wsdl].call(:set_member_ratio, message: message)
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

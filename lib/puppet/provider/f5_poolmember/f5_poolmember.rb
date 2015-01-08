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

  def self.get
  end

  def self.instances
    instances = []
    # Getting all poolmember info from an F5 is not transactional. But we're safe as
    # long as we are the only one doing writes.
    #
    set_activefolder('/')
    enable_recursive_query

    pools   = arraywrap(transport[wsdl].get(:get_list))
    members = arraywrap(transport[wsdl].get(:get_member_v2, { pool_names: { item: pools } }))
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
    instances = instances()

    resources.each do |name, resource|
      if provider = instances.find do |prov|
        "#{prov.pool}:#{prov.name}:#{prov.port}" == resource.title
      end
        resource.provider = provider
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

    [:connection_limit, :description, :priority_group, :rate_limit,
     :ratio].each do |x|
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

  def priority_group=(value)
    @property_flush[:priority_group] = value
  end

  def rate_limit=(value)
    @property_flush[:rate_limit] = value
  end

  def ratio=(value)
    @property_flush[:ratio] = value
  end

  ###########################################################################
  # Flush
  ###########################################################################
  def flush
    addressport = { address: resource[:node], port: resource[:port] }
    @poolmember = {
      pool_names: { item: resource[:pool] },
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

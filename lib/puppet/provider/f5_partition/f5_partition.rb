require 'puppet/provider/f5'

Puppet::Type.type(:f5_partition).provide(:f5_partition, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 partition"

  mk_resource_methods

  confine :feature => :ruby_savon
  defaultfor :feature => :ruby_savon

  def initialize(value={})
    super(value)
    @property_flush = {}
  end

  def self.wsdl
    'Management.Folder'
  end

  def wsdl
    self.class.wsdl
  end

  def self.debug(msg)
    Puppet.debug("(F5_Partition): #{msg}")
  end

  def debug(msg)
    self.class.debug(msg)
  end

  def self.instances
    debug("Puppet::Device::F5: setting active partition to: /")
    transport['System.Session'].call(:set_active_folder, message: { folder: '/' })
    transport['System.Session'].call(:set_recursive_query_state, message: { state: 'STATE_ENABLED' })

    partitions = arraywrap(transport[wsdl].get(:get_list))
    getmsg     = { folders: { item: partitions } }

    descriptions                = arraywrap(transport[wsdl].get(:get_description, getmsg)).collect do |desc|
      desc.nil? ? "" : desc
    end
    device_groups               = arraywrap(transport[wsdl].get(:get_device_group, getmsg))
    traffic_groups              = arraywrap(transport[wsdl].get(:get_traffic_group, getmsg))

    instances = []
    partitions.each_index do |x|
    instances << new( 
       :name                       => partitions[x],
       :ensure                     => :present,
       :description                => descriptions[x],
       :device_group               => device_groups[x],
       :traffic_group              => traffic_groups[x],
      )
    end

    instances
  end

  def self.prefetch(resources)
    f5_partitions = instances

    resources.keys.each do |name|
      if provider = f5_partitions.find{ |partition| partition.name == name }
        resources[name].provider = provider
      end
    end
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    @property_flush[:ensure]        = :create
    @property_flush[:description]   = resource[:description]
    @property_flush[:device_group]  = resource[:device_group]
    @property_flush[:traffic_group] = resource[:traffic_group]
  end

  def destroy
    @property_flush[:ensure] = :destroy
  end

  def description=(value)
    @property_flush[:description] = value
  end

  def device_group=(value)
    @property_flush[:device_group] = value
  end

  def traffic_group=(value)
    @property_flush[:traffic_group] = value
  end

  def flush
    transport['System.Session'].call(:set_active_folder, message: { folder: '/' })
    folder = { folders: { item: resource[:name] } }

    if @property_flush[:ensure] == :destroy
      transport[wsdl].call(:delete_folder, message: folder )
      return
    end

    begin
      transport['System.Session'].call(:start_transaction)

      if @property_flush[:ensure] == :create
        transport[wsdl].call(:create, message: folder)
      end

      unless resource[:description].nil?
        transport[wsdl].call(:set_description, message: folder.merge({ descriptions: { item: resource[:description] } }) )
      end
  
      unless resource[:device_group].nil?
        transport[wsdl].call(:set_device_group, message: folder.merge({ groups: { item: resource[:device_group] } }) )
      end
  
      unless resource[:traffic_group].nil?
        transport[wsdl].call(:set_traffic_group, message: folder.merge({ groups: { item: resource[:traffic_group] } }) )
      end

      transport['System.Session'].call(:submit_transaction)
    rescue Exception
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

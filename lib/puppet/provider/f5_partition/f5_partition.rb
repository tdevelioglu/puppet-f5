require 'puppet/provider/f5'

Puppet::Type.type(:f5_partition).provide(:f5_partition, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 partition"

  mk_resource_methods

  confine :feature => :posix
  confine :feature => :ruby_f5_icontrol
  defaultfor :feature => :posix

  def self.wsdl
    'Management.Folder'
  end

  def wsdl
    self.class.wsdl
  end

  def self.instances
    Puppet.debug("Puppet::Device::F5: setting active partition to: /")
    transport['System.Session'].set_active_folder('/')
    transport['System.Session'].set_recursive_query_state('STATE_ENABLED')

    partitions                  = transport[wsdl].get_list
    descriptions                = transport[wsdl].get_description(partitions)
    device_groups               = transport[wsdl].get_device_group(partitions)
    traffic_groups              = transport[wsdl].get_traffic_group(partitions)
    is_device_group_inheriteds  = transport[wsdl].is_device_group_inherited(partitions)
    is_traffic_group_inheriteds = transport[wsdl].is_traffic_group_inherited(partitions)

    instances = []
    partitions.each_index do |x|
    instances << new( 
       :name                       => partitions[x],
       :ensure                     => :present,
       :description                => descriptions[x],
       :device_group               => device_groups[x],
       :traffic_group              => traffic_groups[x],
       :is_device_group_inherited  => is_device_group_inheriteds[x],
       :is_traffic_group_inherited => is_traffic_group_inheriteds[x],
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
    @property_hash[:ensure] = :present

    @create = true
  end

  def destroy
    @property_hash[:ensure] = :absent
  end

  def flush
    Puppet.debug("Puppet::Provider::F5_Partition: Flushing F5 partition #{resource[:name]}")

    Puppet.debug("Puppet::Device::F5: setting active partition to: /.")
    transport['System.Session'].set_active_folder('/')

    Puppet.debug("Property_hash ensure = #{@property_hash[:ensure]}")
    case @property_hash[:ensure]
    when :absent
      Puppet.debug("Puppet::Provider::F5_Partition: Destroying F5 partition #{resource[:name]}")
      transport[wsdl].delete_folder([resource[:name]])
    when :present

      if @create
        Puppet.debug("Puppet::Provider::F5_Partition: creating F5 partition #{resource[:name]}")
        transport[wsdl].create([resource[:name]])
      end

      Puppet.debug("Puppet::Provider::F5_Partition: Starting transaction partition #{resource[:name]}")
      transport['System.Session'].start_transaction

      Puppet.debug("Puppet::Provider::F5_Partition: Updating F5 partition #{resource[:name]}")
      unless resource[:description].nil?
        transport[wsdl].set_description([resource[:name]], [resource[:description]])
      end
  
      unless resource[:device_group].nil?
        transport[wsdl].set_device_group([resource[:name]], [resource[:device_group]])
      end
  
      unless resource[:traffic_group].nil?
        transport[wsdl].set_ratio([resource[:name]], [resource[:traffic_group]])
      end

      Puppet.debug("Puppet::Provider::F5_Partition: Committing transaction partition #{resource[:name]}")
      transport['System.Session'].submit_transaction
    end

  end

end

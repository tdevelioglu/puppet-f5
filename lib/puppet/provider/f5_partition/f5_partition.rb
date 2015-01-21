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

  def self.soapget_attribute(method)
    super(method, :folders)
  end

  def self.instances
    set_activefolder('/')
    enable_recursive_query

    descriptions   = soapget_attribute(:get_description).collect { |desc| desc.nil? ? "" : desc }
    device_groups  = soapget_attribute(:get_device_group)
    traffic_groups = soapget_attribute(:get_traffic_group)

    instances = []
    soapget_names.each_index do |x|
    instances << new( 
       :description                => descriptions[x],
       :device_group               => device_groups[x],
       :ensure                     => :present,
       :name                       => soapget_names[x],
       :traffic_group              => traffic_groups[x],
      )
    end
    instances
  end

  def self.prefetch(resources)
    partitions = instances

    resources.keys.each do |name|
      if provider = partitions.find{ |partition| partition.name == name }
        resources[name].provider = provider
      end
    end
  end

  def flush
    set_activefolder('/Common')
    @partition = { folders: { item: resource[:name] } }

    if @property_flush[:ensure] == :destroy
      soapcall(:delete_folder)
      return
    end

    if @property_flush[:ensure] == :create
      soapcall(:create)
    end

    # For some reason we can't create and set inside the same transaction.
    if @property_flush.keys.any? { |key| key != :ensure }
      begin
        start_transaction
        if !@property_flush[:description].nil?
          soapcall(:set_description, :descriptions, @property_flush[:description])
        end
    
        if !@property_flush[:device_group].nil?
          soapcall(:set_device_group, :groups, @property_flush[:device_group])
        end
    
        if !@property_flush[:traffic_group].nil?
          soapcall(:set_traffic_group, :groups, @property_flush[:traffic_group])
        end
        submit_transaction
      rescue Exception
        begin
          rollback_transaction
        rescue Exception => e
          if !e.message.include?("No transaction is open to roll back")
            raise
          end
        end
        raise
      end
    end
    @property_hash = resource.to_hash
  end

  ###########################################################################
  # Soap caller (TODO: This should be moved to Provider::F5)
  ###########################################################################
  def soapcall(method, key=nil, value=nil, nest=false)
    soapitem = nest ? { item: { item: value } } : { item:  value }

    message = key.nil? ?  @partition : @partition.merge(key => soapitem)
    transport[wsdl].call(method, message: message)
  end
end

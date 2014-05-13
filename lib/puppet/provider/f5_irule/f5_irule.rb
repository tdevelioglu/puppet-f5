require 'puppet/provider/f5'

Puppet::Type.type(:f5_irule).provide(:f5_irule, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 irules"

  mk_resource_methods

  confine :feature => :posix
  confine :feature => :ruby_f5_icontrol
  defaultfor :feature => :posix

  def initialize(value={})
    super(value)
    @property_flush = {}
  end

  def self.wsdl
    'LocalLB.Rule'
  end

  def wsdl
    self.class.wsdl
  end

  def self.instances
    instances = []

    # Getting all poolmember info from an F5 is not transactional. But we're safe as
    # long as we are the only one doing writes.
    #
    Puppet.debug("Puppet::Device::F5: setting active partition to: /")
    transport['System.Session'].set_active_folder('/')
    transport['System.Session'].set_recursive_query_state('STATE_ENABLED')

    rule_names = transport[wsdl].get_list
    rules      = transport[wsdl].query_all_rules

    # We need to add the rules that have an empty definition as those are not returned by
    # query_all_rules.
    empty_def_rules = []
    rule_names.each do |rule_name|
      if rules.find { |rule| rule["rule_name"] == rule_name }.nil?
        empty_def_rules << { "rule_name" => rule_name, "rule_definition" => "" }
      end
    end
    rules += empty_def_rules

    rules.each do |rule|
      instances << new(
        :name       => rule["rule_name"],
        :ensure     => :present,
        :definition => rule["rule_definition"]
      )
    end

    rule_names.reject! do |rule_name|
      rules.find do |rule|
        rule["rule_name"] == rule_name
      end
    end

    instances
  end

  def self.prefetch(resources)
    f5_irules = instances

    resources.keys.each do |name|
      if provider = f5_irules.find{ |irule| irule.name == name }
        resources[name].provider = provider
      end
    end
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    @property_flush[:ensure]     = :create
    @property_flush[:definition] = resource[:definition]
  end

  def destroy
    @property_flush[:ensure] = :destroy
  end

  def definition=(value)
    @property_flush[:definition] = value
  end

  def flush
    partition = File.dirname(resource[:name])
    rule_definition = {
      "rule_name"       => resource[:name],
      "rule_definition" => @property_flush[:definition]
    }

    Puppet.debug("Puppet::Device::F5: setting active partition to: #{partition}")
    transport['System.Session'].set_active_folder(partition)

    if @property_flush[:ensure] == :destroy
      transport[wsdl].delete_rule([resource[:name]])
      return
    end

    begin
      transport['System.Session'].start_transaction

      if @property_flush[:ensure] == :create
        transport[wsdl].create([{ "rule_name" => resource[:name] }])
      end

      unless @property_flush[:definition].nil?
        transport[wsdl].modify_rule([rule_definition])
      end
  
      transport['System.Session'].submit_transaction
    rescue Exception => e
      raise e
      transport['System.Session'].rollback_transaction
    end

  end

end

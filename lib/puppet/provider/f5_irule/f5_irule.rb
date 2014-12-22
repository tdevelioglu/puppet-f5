require 'puppet/provider/f5'

Puppet::Type.type(:f5_irule).provide(:f5_irule, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 irules"

  mk_resource_methods

  confine :feature => :ruby_savon
  defaultfor :feature => :ruby_savon

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

    set_activefolder('/')
    transport['System.Session'].call(:set_recursive_query_state, message: { state: 'STATE_ENABLED' })

    rule_names = arraywrap(transport[wsdl].get(:get_list))
    rules      = arraywrap(transport[wsdl].get(:query_all_rules))

    # We need to add the rules that have an empty definition as those are not returned by
    # query_all_rules.
    empty_def_rules = []
    rule_names.each do |rule_name|
      if rules.find { |rule| rule[:rule_name] == rule_name }.nil?
        empty_def_rules << { rule_name: rule_name, rule_definition: "" }
      end
    end
    rules += empty_def_rules

    rules.each do |rule|
      instances << new(
        :name       => rule[:rule_name],
        :ensure     => :present,
        :definition => rule[:rule_definition]
      )
    end

    rule_names.reject! do |rule_name|
      rules.find do |rule|
        rule[:rule_name] == rule_name
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
    rule = {
      rules: {
        item: {
          rule_name: resource[:name],
          rule_definition: @property_flush[:definition]
        }
      }
    }

    set_activefolder(partition)

    if @property_flush[:ensure] == :destroy
      transport[wsdl].call(:delete_rule, message: rule)
      return
    end

    if @property_flush[:ensure] == :create
      transport[wsdl].call(:create, message: rule)
    else
      unless @property_flush[:definition].nil?
        transport[wsdl].call(:modify_rule, message: rule)
      end
    end

    @property_hash = resource.to_hash
  end
end

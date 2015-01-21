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
    enable_recursive_query

    rule_names = soapget_names(:get_list)
    rules      = arraywrap(transport[wsdl].get(:query_all_rules))

    # We need to add the rules that have an empty definition as those are not
    # returned by query_all_rules.
    empty_def_rules = []
    rule_names.each do |rule_name|
      if !rules.any? { |rule| rule[:rule_name] == rule_name }
        empty_def_rules << { rule_name: rule_name, rule_definition: "" }
      end
    end
    rules += empty_def_rules

    rules.each do |rule|
      instances << new(
        :definition => rule[:rule_definition],
        :ensure     => :present,
        :name       => rule[:rule_name]
      )
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

  def flush
    @rule = { rule_name: resource[:name],
              rule_definition: @property_flush[:definition] }
    set_activefolder('/Common')

    if @property_flush[:ensure] == :destroy
      soapcall(:delete_rule)
      return
    end

    if @property_flush[:ensure] == :create
      transport[wsdl].call(:create)
    else
      if !@property_flush[:definition].nil?
        soapcall(:modify_rule)
      end
    end

    @property_hash = resource.to_hash
  end

  ###########################################################################
  # Soap caller (TODO: This should be moved to Provider::F5)
  ###########################################################################
  def soapcall(method, key=nil, value=nil, nest=false)
    soapitem = nest ? { item: { item: value } } : { item:  value }

    message = key.nil? ?  @rule : @rule.merge(key => soapitem)
    transport[wsdl].call(method, message: message)
  end
end

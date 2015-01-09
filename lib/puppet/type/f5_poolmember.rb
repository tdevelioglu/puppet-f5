Puppet::Type.newtype(:f5_poolmember) do
  @doc = "Manages F5 poolmembers."

  apply_to_device

  ensurable do
    defaultvalues
    defaultto :present
  end

  def initialize(resource)
    super
    self.title = "#{resource[:pool]}:#{resource[:node]}:#{resource[:port]}"
  end

  def self.title_patterns
    [
      [ /^(([^:]+):([^:]+):([0-9]+))$/m,
        [
          [:name, lambda{|x| x}],
          [:pool, lambda{|x| x}],
          [:node, lambda{|x| x}],
          [:port, lambda{|x| x}]
        ]
      ],
      [ /^(([^:]+):([0-9]+))$/m,
        [
          [:name, lambda{|x| x }],
          [:node, lambda{|x| x}],
          [:port, lambda{|x| x }]
        ]
      ],
      [ /^(([^:]+):([^:]+))$/m,
        [
          [:name, lambda{|x| x }],
          [:pool, lambda{|x| x }],
          [:node, lambda{|x| x }],
        ]
      ],
      [ /((.*))/m,
        [
          [:name, lambda{|x| x }],
          [:node, lambda{|x| x }]
        ]
      ]
    ]
  end
 
  newparam(:name, :namevar=>true) do
    desc "The poolmember name."

    validate do |value|
      unless Puppet::Util.absolute_path?(value)
        fail Puppet::Error, "Poolmember names must be fully qualified, not '#{value}'"
      end
    end
  end

  newparam(:node, :namevar=>true) do
    desc "The node. In v11+ this is the node name"

    validate do |value|
      unless Puppet::Util.absolute_path?(value)
        fail Puppet::Error, "Poolmember node name must be fully qualified, not '#{value}'"
      end
    end
  end

  newparam(:pool, :namevar => true) do
    desc "The pool name."

    validate do |value|
      unless Puppet::Util.absolute_path?(value)
        fail Puppet::Error, "Pools must be fully qualified, not '#{value}'"
      end
    end
  end

  newparam(:port, :namevar => true) do
    desc "The port of the poolmember"

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'port' must be a number, not '#{value}'"
      end
    end
  end

  newproperty(:connection_limit) do
    desc "The connection limit of the poolmember."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'connection_limit' must be a number, not '#{value}'"
      end
    end
  end

  newproperty(:description) do
    desc "The description of the poolmember."
  end

  newproperty(:priority_group) do
    desc "The priority group of the poolmember."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'priority_group' must be a number, not '#{value}'"
      end
    end
  end

  newproperty(:rate_limit) do
    desc "The rate limit of the poolmember."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'rate_limit' must be a number, not '#{value}'"
      end
    end
  end

  newproperty(:ratio) do
    desc "The ratio of the poolmember."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'port' must be a number, not '#{value}'"
      end
    end
  end

  ###########################################################################
  # Properties for at-creation only
  ###########################################################################
  # These properties exist because, often, we want objects to be *created*
  # with property values X, but still let the human operator change them
  # without puppet getting in the way.
  #
  # The atcreate properties are "special" as in that they are only used at
  # creation. This causes a problem because there is no value to speak of after
  # create.
  # Thus we consider atcreate properties always in sync.
  newproperty(:atcreate_connection_limit) do
    desc "The connection limit of the poolmember at creation."

    def insync?(is)
      true
    end

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'atcreate_connection_limit' must be a number, not '#{value}'"
      end
    end
  end

  newproperty(:atcreate_description) do
    desc "The description of the poolmember at creation."

    def insync?(is)
      true
    end

  end

  newproperty(:atcreate_priority_group) do
    desc "The priority group of the poolmember at creation."

    def insync?(is)
      true
    end

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'atcreate_priority_group' must be a number, not '#{value}'"
      end
    end
  end

  newproperty(:atcreate_rate_limit) do
    desc "The rate_limit for the poolmember at creation."

    def insync?(is)
      true
    end

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'atcreate_rate_limit' must be a number, not '#{value}'"
      end
    end
  end

  newproperty(:atcreate_ratio) do
    desc "The ratio of the poolmember at creation."

    def insync?(is)
      true
    end

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'atcreate_port' must be a number, not '#{value}'"
      end
    end
  end

  ###########################################################################
  # Validation
  ###########################################################################
  validate do
    if self[:ensure] == :present
      if self[:pool].nil?
        fail Puppet::Error, "Parameter 'pool' must be defined"
      end
  
      if self[:port].nil?
        fail Puppet::Error, "Parameter 'port' must be defined"
      end
    end
  end

  autorequire(:f5_pool) do
    self[:pool]
  end

  autorequire(:f5_node) do
    self[:node]
  end

end

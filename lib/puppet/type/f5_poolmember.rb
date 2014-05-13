Puppet::Type.newtype(:f5_poolmember) do
  @doc = "Manages F5 poolmembers."

  apply_to_device

  ensurable do
    defaultvalues
    defaultto :present
  end

  def initialize(resource)
    super
    self.title = "#{resource[:pool]}:#{resource[:name]}:#{resource[:port]}"
  end

  def self.title_patterns
    [
      [ /^([^:]+):([^:]+):([0-9]+)$/m,
        [
          [:pool, lambda{|x| x}],
          [:name, lambda{|x| x}],
          [:port, lambda{|x| x}]
        ]
      ],
      [ /^([^:]+):([0-9]+)$/m,
        [
          [:name, lambda{|x| x }],
          [:port, lambda{|x| x }]
        ]
      ],
      [ /^([^:]+):([^:]+)$/m,
        [
          [:pool, lambda{|x| x }],
          [:name, lambda{|x| x }]
        ]
      ],
      [ /(.*)/m,
        [
          [:name, lambda{|x| x }]
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

  newparam(:pool, :namevar => true) do
    desc "The pool name."

    validate do |value|
      unless Puppet::Util.absolute_path?(value)
        fail Puppet::Error, "Pools must be fully qualified, not '#{value}'"
      end
    end
  end

  newparam(:port, :namevar => true) do
    desc "The portnumber"

    validate do |value|
      unless /^\d+$/.match(value)
        fail Puppet::Error, "port must be a number, not #{value}"
      end
    end

    munge do |value|
      Integer(value)
    end
  end

  newproperty(:connection_limit) do
    desc "The connection limit for the specified poolmember."

    validate do |value|
      unless /^\d+$/.match(value)
        fail Puppet::Error, "connection_limit must be a number, not #{value}"
      end
    end

    munge do |value|
      Integer(value)
    end

    defaultto "0"
  end

  newproperty(:description) do
    desc "The description for the specified poolmember."
  end

  #
  # LocalLB.Pool.get_member_monitor_rule is broken
  #
#  newproperty(:health_monitors, :array_matching => :all) do
#    desc "The health monitors for the specified node.
#    Specify the special value 'none' to disable
#    all monitors.
#    e.g.: ['/Common/icmp'. '/Common/http']"
#
#    # Override the default method because it assumes there is nothing to do if @should is empty
#    def insync?(is)
#      is.sort == @should.sort
#    end
#
#    validate do |value|
#      unless Puppet::Util.absolute_path?(value)
#        fail Puppet::Error, "Health monitors must be fully qualified (e.g. '/Common/http'), not '#{value}'"
#      end
#    end
#
#    defaultto []
#  end

  newproperty(:priority_group) do
    desc "The priority group for the specified node."

    validate do |value|
      unless /^\d+$/.match(value)
        fail Puppet::Error, "priority_group must be a number, not #{value}"
      end
    end

    munge do |value|
      Integer(value)
    end

    defaultto "0"
  end

  newproperty(:rate_limit) do
    desc "The rate_limit for the specified node."

    validate do |value|
      unless /^\d+$/.match(value)
        fail Puppet::Error, "rate_limit must be a number, not #{value}"
      end
    end

    munge do |value|
      Integer(value)
    end

    defaultto "0"
  end

  newproperty(:ratio) do
    desc "The ratios for the specified node."

    validate do |value|
      unless /^\d+$/.match(value)
        fail Puppet::Error, "ratio must be a number, not #{value}"
      end
    end

    munge do |value|
      Integer(value)
    end

    defaultto "1"
  end

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
    self[:name]
  end

end

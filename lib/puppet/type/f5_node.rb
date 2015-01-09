Puppet::Type.newtype(:f5_node) do
  @doc = "Manage F5 node."

  apply_to_device

  ensurable do
    defaultvalues
    defaultto :present
  end

  newparam(:name, :namevar=>true) do
    desc "The node name."

    validate do |value|
      unless Puppet::Util.absolute_path?(value)
        fail Puppet::Error, "Node names must be fully qualified, not '#{value}'"
      end
    end
  end

  newproperty(:connection_limit) do
    desc "The connection limit of the node."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'connection_limit' must be a number, not '#{value}'"
      end
    end
  end

  newproperty(:description) do
    desc "The description of the node."
  end

  newproperty(:dynamic_ratio) do
    desc "The dynamic ratio of the node."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'dynamic_ratio' must be a number, not '#{value}'"
      end
    end

  end

  newproperty(:ipaddress) do
    desc "The ip address of the node"
  end

  newproperty(:health_monitors, :array_matching => :all) do
    desc "The health monitors of the node.
    Specify the special value 'none' to disable
    all monitors.
    e.g.: ['/Common/icmp'. '/Common/http']"

    def should_to_s(newvalue)
      newvalue.inspect
    end

    # Override the default method because it assumes there is nothing to do if @should is empty
    def insync?(is)
      is.sort == @should.sort
    end

    validate do |value|
      unless Puppet::Util.absolute_path?(value) || value == "none" || value == "default"
        fail Puppet::Error, "Health monitors must be fully qualified (e.g. '/Common/http'), not '#{value}'"
      end
    end
  end

  newproperty(:rate_limit) do
    desc "The rate_limit of the node."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'rate_limit' must be a number, not '#{value}'"
      end
    end
  end

  newproperty(:ratio) do
    desc "The ratio of the node."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'ratio' must be a number, not '#{value}'"
      end
    end
  end

  newproperty(:session_status) do
    desc "The states that allows new sessions to be established for the
    specified node addresses."

    validate do |value|
      unless /^(DISABLED|ENABLED)$/.match(value)
        fail Puppet::Error, "session_status must be one of:
          DISABLED,ENABLED, not #{value}"
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
    desc "The connection limit of the node at creation."

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

    defaultto 0 # unlimited
  end

  newproperty(:atcreate_description) do
    desc "The description of the node at creation."

    def insync?(is)
      true
    end
  end

  newproperty(:atcreate_rate_limit) do
    desc "The rate_limit for the node at creation."

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
    desc "The ratio of the node at creation."

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
    if self[:ensure] != :absent and self[:ipaddress].nil?
      fail('ipaddress is required when ensure is present')
    end
  end

  autorequire(:f5_partition) do
    File.dirname(self[:name]) 
  end

  autorequire(:f5_monitor) do
    self[:health_monitors]
  end

end

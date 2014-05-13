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

  newparam(:force, :boolean => true) do
    desc "LocalLB.NodeAddressV2 doesn't support updating ipaddress, so we
      delete-create the node (and not in a transactional way).
      This can potentially leave you with a deleted node!"

    newvalues(:true, :false)

    defaultto :false
  end

  newproperty(:connection_limit) do
    desc "The connection limit for the specified node."

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
    desc "The description for the specified node."
  end

  newproperty(:dynamic_ratio) do
    desc "The dynamic ratio for the specified node."

    validate do |value|
      unless /^\d+$/.match(value)
        fail Puppet::Error, "connection_limit must be a number, not #{value}"
      end
    end

    munge do |value|
      Integer(value)
    end

    defaultto "1"
  end

  newproperty(:ipaddress) do
    desc "The ip address for the specified node"
  end

  newproperty(:health_monitors, :array_matching => :all) do
    desc "The health monitors for the specified node.
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
      unless Puppet::Util.absolute_path?(value)
        fail Puppet::Error, "Health monitors must be fully qualified (e.g. '/Common/http'), not '#{value}'"
      end
    end

    defaultto []
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

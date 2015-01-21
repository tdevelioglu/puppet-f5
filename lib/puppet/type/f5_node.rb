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

  newparam(:ipaddress) do
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

    munge do |value|
      value.upcase
    end

    validate do |value|
      unless /^(DISABLED|ENABLED)$/i.match(value)
        fail Puppet::Error, "session_status must be either
          disabled or enabled, not #{value}"
      end
    end
  end

  ###########################################################################
  # Parameters used at creation.
  ###########################################################################
  # These attributes are parameters because, often, we want objects to be
  # *created* with property values X, but still let a human make changes
  # to them without puppet getting in the way.
  newparam(:atcreate_connection_limit) do
    desc "The connection limit of the node at creation."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'atcreate_connection_limit' must be a number, not '#{value}'"
      end
    end
    defaultto 0 # unlimited
  end

  newparam(:atcreate_description) do
    desc "The description of the node at creation."
  end

  newparam(:atcreate_dynamic_ratio) do
    desc "The dynamic ratio of the node at creation."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'atcreate_dynamic_ratio' must be a number, not '#{value}'"
      end
    end
  end

  newparam(:atcreate_health_monitors) do
    desc "The health monitors of the node at creation.
    Specify the special value 'none' to disable
    all monitors.
    e.g.: ['/Common/icmp'. '/Common/http']"

    validate do |value|
      value = [value] unless value.is_a?(Array)

      value.each do |item|
        unless Puppet::Util.absolute_path?(item) || item == "none" || item == "default"
          fail Puppet::Error, "'atcreate_health_monitors' must be fully"\
            "qualified (e.g. '/Common/http'), not '#{item}'"
        end
      end
    end
  end

  newparam(:atcreate_rate_limit) do
    desc "The rate_limit for the node at creation."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'atcreate_rate_limit' must be a number, not '#{value}'"
      end
    end
  end

  newparam(:atcreate_ratio) do
    desc "The ratio of the node at creation."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'atcreate_port' must be a number, not '#{value}'"
      end
    end
  end

  newparam(:atcreate_session_status) do
    desc "The states that allows new sessions to be established for the
    specified node addresses at creation."

    munge do |value|
      value.upcase
    end

    validate do |value|
      unless /^(DISABLED|ENABLED)$/i.match(value)
        fail Puppet::Error, "atcreate_session_status must be either
          disabled or enabled, not '#{value}'"
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

Puppet::Type.newtype(:f5_partition) do
  @doc = "Manage F5 partition."

  apply_to_device

  ensurable do
    defaultvalues
    defaultto :present
  end

  newparam(:name, :namevar=>true) do
    desc "The partition name."

    validate do |value|
      unless Puppet::Util.absolute_path?(value)
        fail Puppet::Error, "Partition names must be fully qualified, not '#{value}'"
      end
    end

  end

  newproperty(:description) do
    desc "The description of the partition."
  end

  newproperty(:device_group) do
    desc "The device group of the partition."

    validate do |value|
      unless Puppet::Util.absolute_path?(value) || value.to_s.empty?
        fail Puppet::Error, "Device groups must be fully qualified, not '#{value}'"
      end
    end
  end

  newproperty(:traffic_group) do
    desc "The traffic group of the partition."

    validate do |value|
      unless Puppet::Util.absolute_path?(value) || value.to_s.empty?
        fail Puppet::Error, "Traffic groups must be fully qualified, not '#{value}'"
      end
    end
  end

  ###########################################################################
  # Parameters used at creation.
  ###########################################################################
  # These attributes are parameters because, often, we want objects to be
  # *created* with property values X, but still let a human make changes
  # to them without puppet getting in the way.
  newparam(:atcreate_description) do
    desc "The description of the partition at creation."
  end

  newparam(:atcreate_device_group) do
    desc "The device group of the partition at creation."

    validate do |value|
      unless Puppet::Util.absolute_path?(value) || value.to_s.empty?
        fail Puppet::Error, "Device groups must be fully qualified, not '#{value}'"
      end
    end
  end

  newparam(:atcreate_traffic_group) do
    desc "The traffic group of the partition at creation."

    validate do |value|
      unless Puppet::Util.absolute_path?(value) || value.to_s.empty?
        fail Puppet::Error, "Traffic groups must be fully qualified, not '#{value}'"
      end
    end
  end
end

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
    desc "The description for the specified partition."

    defaultto "Managed by puppet"
  end

  newproperty(:device_group) do
    desc "The device group for the specified partition."

    validate do |value|
      unless Puppet::Util.absolute_path?(value) || value.to_s.empty?
        fail Puppet::Error, "Device groups must be fully qualified, not '#{value}'"
      end
    end
  end

  newproperty(:traffic_group) do
    desc "The traffic group for the specified partition."

    validate do |value|
      unless Puppet::Util.absolute_path?(value) || value.to_s.empty?
        fail Puppet::Error, "Traffic groups must be fully qualified, not '#{value}'"
      end
    end
  end

  newproperty(:is_device_group_inherited) do
    desc "The device group for the specified partition."

    validate do |value|
      unless value.nil?
        fail Puppet::Error, "Property 'is_device_group_inherited' is read-only, can not set to '#{value}'"
      end
    end
  end

  newproperty(:is_traffic_group_inherited) do
    desc "The device group for the specified partition."

    validate do |value|
      unless value.nil?
        fail Puppet::Error, "Property 'is_traffic_group_inherited' is read-only, can not set to '#{value}'"
      end
    end
  end

end

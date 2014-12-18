Puppet::Type.newtype(:f5_irule) do
  @doc = "Manages F5 iRules."

  apply_to_device

  ensurable do
    defaultvalues
    defaultto :present
  end

  newparam(:name, :namevar=>true) do
    desc "The iRule name."

    validate do |value|
      unless Puppet::Util.absolute_path?(value)
        fail Puppet::Error, "Poolmember names must be fully qualified, not '#{value}'"
      end
    end
  end

  newproperty(:definition) do
    desc "The definition of the iRule."
  end

  autorequire(:f5_partition) do
    File.dirname(self[:name]) 
  end

  validate do
    if self[:ensure] == :present
      if self[:definition].nil?
        fail Puppet::Error, "Parameter 'definition' must be defined"
      end
    end
  end

end

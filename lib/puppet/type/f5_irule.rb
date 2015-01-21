Puppet::Type.newtype(:f5_irule) do
  @doc = "Manages F5 iRules."

  apply_to_device

  ensurable do
    defaultvalues
    defaultto :present
  end

  newparam(:name, :namevar=>true) do
    desc "The irule name."

    validate do |value|
      unless Puppet::Util.absolute_path?(value)
        fail Puppet::Error, "Irule names must be fully qualified, not '#{value}'"
      end
    end
  end

  newproperty(:definition) do
    desc "The definition of the irule."
  end

  autorequire(:f5_partition) do
    File.dirname(self[:name]) 
  end

  ###########################################################################
  # Parameters used at creation.
  ###########################################################################
  # These attributes are parameters because, often, we want objects to be
  # *created* with property values X, but still let a human make changes
  # to them without puppet getting in the way.
  newparam(:atcreate_definition) do
    desc "The definition of the irule at creation."

    defaultto ""
  end
end

Puppet::Type.newtype(:f5_virtualserver) do
  @doc = "Manages F5 virtualservers."

  apply_to_device

  ensurable do
    defaultvalues
    defaultto :present
  end

  newparam(:name, :namevar=>true) do
    desc "The virtualserver name."

    validate do |value|
      unless Puppet::Util.absolute_path?(value)
        fail Puppet::Error, "Virtualserver names must be fully qualified, not '#{value}'"
      end
    end
  end

  newproperty(:description) do
    desc "The virtualserver description"

    defaultto "Managed by Puppet"
  end

  newproperty(:address) do
    desc "The virtualserver address"
  end

  newproperty(:default_pool) do
    desc "The virtualserver default pool"
  end

  newproperty(:port) do
    desc "The virtualserver port"

    validate do |value|
      unless /^\d+$/.match(value)
        fail Puppet::Error, "Parameter 'port' must be a number, not '#{value}'"
      end
    end

    munge do |value|
      Integer(value)
    end

  end

  newproperty(:fallback_persistence_profile) do
    desc "The virtualserver fallback persistence profile"
  end

  newproperty(:persistence_profile) do
    desc "The virtualserver default persistence profile"
  end

  newproperty(:protocol) do
    desc "The virtualserver default persistence profile"

    def should=(values)
      super(values.upcase)
    end

    validate do |value|
      valid_protocols =
        ["ANY", "IPV6", "ROUTING", "NONE", "FRAGMENT", "DSTOPTS", "TCP", "UDP", "ICMP", "ICMPV6",
         "OSPF", "SCTP", "UNKNOWN"]

      unless valid_protocols.include?(value)
        fail Puppet::Error, "Parameter '#{self.name}' must be one of: #{valid_protocols.inspect}, not '#{value}'"
      end
    end

    munge do |value|
      value.upcase
    end

    defaultto "TCP"
  end

  newproperty(:profiles, :array_matching => :all) do
    desc "The virtualserver profiles"

    # Default insync? returns true when property value is empty array
    def insync?(is)
      is.sort == @should.sort
    end

    # Get rid of standard profiles
    def retrieve
      super - ["/Common/tcp", "/Common/udp"]
    end

    def should_to_s(newvalue)
      newvalue.inspect
    end
  end

  newproperty(:type) do
    desc "The virtualserver type"

    def should=(values)
      super(values.upcase)
    end

    validate do |value|
      valid_types =
        ["POOL", "IP_FORWARDING", "L2_FORWARDING", "REJECT", "FAST_L4", "FAST_HTTP", "STATELESS",
         "DHCP_RELAY", "UNKNOWN", "INTERNAL"]

      unless valid_types.include?(value)
        fail Puppet::Error, "Parameter 'type' must be one of: #{valid_types.inspect}, not '#{value}'"
      end
    end

    defaultto "POOL"
  end

  newproperty(:wildmask) do
    desc "The virtualserver wildmask"

    defaultto "255.255.255.255"
  end

  validate do
    if self[:ensure] == :present
      if self[:address].nil?
        fail Puppet::Error, "Parameter 'address' must be defined"
      end

      if self[:port].nil?
        fail Puppet::Error, "Parameter 'port' must be defined"
      end

    end
  end

  autorequire(:f5_partition) do
    File.dirname(self[:name]) 
  end

  autorequire(:f5_profile) do
    self[:profiles] unless (self[:profiles].nil? self[:profiles].empty?)
  end

  autorequire(:f5_pool) do
    self[:default_pool] unless (self[:default_pool].nil? || self[:default_pool].empty?)
  end

end

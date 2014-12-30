Puppet::Type.newtype(:f5_pool) do
  @doc = "Manage F5 pool."

  apply_to_device

  ensurable do
    defaultvalues

    defaultto :present
  end

  newparam(:name, :namevar=>true) do
    desc "The pool name."

    validate do |value|
      unless Puppet::Util.absolute_path?(value)
        fail Puppet::Error, "Pool names must be fully qualified, not '#{value}'"
      end
    end

  end

  newparam(:membership) do
    desc "Whether the list of members should be considered the exact or the
    minimum list of members that should in the pool.
    Defaults to `minimum`."

    newvalues(:exact, :minimum)

    defaultto :minimum
  end

  newproperty(:description) do
    desc "The description of the specified pool."
  end

  newproperty(:lb_method) do
    desc "The load balancing methods for the specified pools."

    def should=(values)
      super(values.upcase)
    end

    validate do |value|
      valid_lb_methods =
        ["ROUND_ROBIN", "RATIO_MEMBER", "LEAST_CONNECTION_MEMBER", "OBSERVED_MEMBER",
         "PREDICTIVE_MEMBER", "RATIO_NODE_ADDRESS", "LEAST_CONNECTION_NODE_ADDRESS",
         "FASTEST_NODE_ADDRESS", "OBSERVED_NODE_ADDRESS", "PREDICTIVE_NODE_ADDESS", "DYNAMIC_RATIO",
         "FASTEST_APP_RESPONSE", "LEAST_SESSIONS", "DYNAMIC_RATIO_MEMBER", "L3_ADDR", "UNKNOWN",
         "WEIGHTED_LEAST_CONNECTION_MEMBER", "WEIGHTED_LEAST_CONNECTION_NODE_ADDRESS",
         "RATIO_SESSION", "RATIO_LEAST_CONNECTION_MEMBER", "RATIO_LEAST_CONNECTION_NODE_ADDRESS"]

      unless valid_lb_methods.include?(value)
        fail Puppet::Error, "Parameter 'lb_method' must be one of #{valid_lb_methods.inspect},\
        not '#{value}"
      end
    end
  end

  newproperty(:members, :array_matching => :all) do
    desc "The list of pool members. This must be a hash or list of hashes.
    e.g.: [{'address': '/Common/pc109xml-01', 'port': 443}]"

    def should_to_s(newvalue)
      newvalue.inspect
    end

    def is_to_s(currentvalue)
      currentvalue.inspect
    end

    def should
      return nil unless defined?(@should)

      should = @should
      is = retrieve

      if @resource[:membership] != :exact
        should += is if is.is_a?(Array)
      end

      should.uniq
    end

    def insync?(is)
      return true unless is

      if is == :absent
        is = []
      end

      is.sort_by(&:hash) == self.should.sort_by(&:hash)
    end

    validate do |value|
      unless value.is_a?(Hash)
        fail Puppet::Error, "Members must be hashes, not #{value}"
      end

      unless Puppet::Util.absolute_path?(value["address"])
        fail Puppet::Error, "Member names must be fully qualified, not '#{value["address"]}'"
      end
    end

    munge do |value|
      { address: value["address"], port: value["port"] }
    end

  end

  newproperty(:health_monitors, :array_matching => :all) do
    desc "The health monitors for the specified pools."

    def should_to_s(newvalue)
      newvalue.inspect
    end

    def insync?(is)
      is.sort == @should.sort
    end
  end

  autorequire(:f5_partition) do
    File.dirname(self[:name])
  end

  autorequire(:f5_monitor) do
    self[:health_monitors]
  end  

  autorequire(:f5_node) do
    if !self[:members].nil?
      self[:members].collect do |member|
        member['address']
      end
    end
  end

end

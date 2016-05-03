Puppet::Type.newtype(:f5_poolmember) do
  @doc = "Manages F5 poolmembers."

  apply_to_device

  ensurable do
    defaultvalues
    defaultto :present
  end

  attr_reader :pool, :node, :port

  def initialize(*args)
    super
    @pool, @node, @port = self[:name].split(':')
  end

  newparam(:name, :namevar=>true) do
    desc "The poolmember name."

    validate do |value|
      unless value =~ /^[^:]+:[^:]+:\d+$/
        raise ArgumentError, 'Resource name must follow the format'\
          ' "<pool>:<node>:<port>"'
      end
      pool, node, port = value.split(':')

      unless Puppet::Util.absolute_path?(pool)
        raise ArgumentError, "pool component of resource title must be fully "\
           " qualified, not \"#{pool}\""
      end

      unless Puppet::Util.absolute_path?(node)
        raise ArgumentError, "node component of resource title must be fully"\
         " qualified, not \"#{node}\""
      end

      unless port =~ /\d+/
        raise ArgumentError, "port component of resource title must be numeric"
          ", not \"#{port}\""
      end
    end
  end

  newparam(:node) do
    desc "Deprecated, set as part of resource title instead."
  end

  newparam(:pool) do
    desc "Deprecated, set as part of resource title instead."
  end

  newparam(:port) do
    desc "Deprecated, set as part of resource title instead."
  end

  newproperty(:connection_limit) do
    desc "The connection limit of the poolmember."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'connection_limit' must be a number, not '#{value}'"
      end
    end
  end

  newproperty(:description) do
    desc "The description of the poolmember."
  end

  newproperty(:priority_group) do
    desc "The priority group of the poolmember."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'priority_group' must be a number, not '#{value}'"
      end
    end
  end

  newproperty(:rate_limit) do
    desc "The rate limit of the poolmember."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'rate_limit' must be a number, not '#{value}'"
      end
    end
  end

  newproperty(:ratio) do
    desc "The ratio of the poolmember."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'port' must be a number, not '#{value}'"
      end
    end
  end

  newproperty(:session_status) do
    desc "Session status of the poolmember."

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
    desc "The connection limit of the poolmember at creation."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'atcreate_connection_limit' must be a number, not '#{value}'"
      end
    end
  end

  newparam(:atcreate_description) do
    desc "The description of the poolmember at creation."
  end

  newparam(:atcreate_priority_group) do
    desc "The priority group of the poolmember at creation."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'atcreate_priority_group' must be a number, not '#{value}'"
      end
    end
  end

  newparam(:atcreate_rate_limit) do
    desc "The rate_limit for the poolmember at creation."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'atcreate_rate_limit' must be a number, not '#{value}'"
      end
    end
  end

  newparam(:atcreate_ratio) do
    desc "The ratio of the poolmember at creation."

    munge do |value|
      begin
        Integer(value)
      rescue
        fail Puppet::Error, "'atcreate_port' must be a number, not '#{value}'"
      end
    end
  end

  newparam(:atcreate_session_status) do
    desc "The session status of the poolmember at creation."

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
  # Validation / Autorequire
  ###########################################################################
  autorequire(:f5_pool) do
    @pool
  end

  autorequire(:f5_node) do
    @node
  end

end

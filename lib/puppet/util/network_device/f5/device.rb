require 'uri'
require 'puppet/util/network_device/f5/facts'
require 'puppet/util/network_device/f5/transport'

class Puppet::Util::NetworkDevice::F5::Device

  attr_accessor :url, :transport
  attr_reader   :active_folder, :recursive_query_state

  def initialize(url, option = {})
    @url = URI.parse(url)
    @option = option

    modules = [
      'LocalLB.Class',
      'LocalLB.Monitor',
      'LocalLB.NodeAddressV2',
      'LocalLB.ProfileClientSSL',
      'LocalLB.ProfilePersistence',
      'LocalLB.Pool',
      'LocalLB.PoolMember',
      'LocalLB.Rule',
      'LocalLB.SNAT',
      'LocalLB.SNATPool',
      'LocalLB.SNATTranslationAddress',
      'LocalLB.VirtualServer',
      'Management.Folder',
      'Management.KeyCertificate',
      'Management.Partition',
      'Management.SNMPConfiguration',
      'Management.UserManagement',
      'Networking.RouteTableV2',
      'System.ConfigSync',
      'System.Failover',
      'System.Inet',
      'System.Session',
      'System.SystemInfo'
    ]

    Puppet.debug("(F5 device) connecting to F5 device #{@url.host}.")
    @transport ||= Puppet::Util::NetworkDevice::F5::Transport.new(@url.host, @url.user, @url.password, modules).get_interfaces

    Puppet.debug("(F5 device) raising transaction timeout to 15s.")
    transport['System.Session'].call(:set_transaction_timeout, message: { timeout: 15 })

    Puppet.debug("(F5 device) setting active partition to /.")
    self.active_folder = '/'
  end

  def active_folder=(value)
    return if @active_folder == value

    Puppet.debug("(F5 device) Setting active folder to '#{value}'")
    transport['System.Session'].call(
      :set_active_folder, message: { folder: value })
    @active_folder = value
  end

  def recursive_query_state=(value)
    return if value == @recursive_query_state

    state = value ? 'STATE_ENABLED' : 'STATE_DISABLED'
    Puppet.debug("(F5 device) Setting recursive_query_state to #{state}")
    transport['System.Session'].call(
      :set_recursive_query_state, message: { state: state })
    @recursive_query_state = value
  end

  def facts
    @facts ||= Puppet::Util::NetworkDevice::F5::Facts.new(@transport)
    facts = @facts.retrieve
    Puppet.debug("(F5 device) Facts retrieved: #{facts}")
    facts
  end
end

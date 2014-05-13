require 'uri'
require 'f5-icontrol'
require 'puppet/util/network_device/f5/facts'

class Puppet::Util::NetworkDevice::F5::Device

  attr_accessor :url, :transport, :partition

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
      'Networking.RouteTable',
      'System.ConfigSync',
      'System.Inet',
      'System.Session',
      'System.SystemInfo'
    ]

    Puppet.debug("Puppet::Device::F5: connecting to F5 device #{@url.host}.")
    @transport ||= F5::IControl.new(@url.host, @url.user, @url.password, modules).get_interfaces

    Puppet.debug("Puppet::Device::F5: raising transaction timeout to 15s.")
    transport['System.Session'].set_transaction_timeout(15)

    Puppet.debug("Puppet::Device::F5: setting active partition to /.")
    transport['System.Session'].set_active_folder('/')

  end

  def facts
    @facts ||= Puppet::Util::NetworkDevice::F5::Facts.new(@transport)
    facts = @facts.retrieve

    # inject F5 partition info.
    facts['partition'] = @partition
    facts
  end
end

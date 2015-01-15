require 'puppet/util/network_device/f5/device'
require 'base64'

class Puppet::Provider::F5 < Puppet::Provider
  attr_writer :device

  def self.device
    # If @device is nil, we're probably being called at the first prefetch.
    transport if @device.nil?
    @device
  end

  # convert 64bit Integer to F5 representation as {:high => 32bit, :low => 32bit}
  def to_32h(value)
    high = (value.to_i & 0xFFFFFFFF00000000) >> 32
    low  = value.to_i & 0xFFFFFFFF
    {:high => high, :low => low}
  end

  # convert F5 representation of 64 bit to string (since Puppet compares string rather than int)
  def to_64s(value)
    ((value[:high].to_i << 32) + value[:low].to_i).to_s
  end

  def network_address(value)
    value.sub(":" + value.split(':').last, '')
  end

  def network_port(value)
    port = value.split(':').last
    port.to_i unless port == '*'
    port
  end

  def self.transport
    if Facter.value(:url) then
      Puppet.debug "Puppet::Util::NetworkDevice::F5: connecting via facter url."
      @device ||= Puppet::Util::NetworkDevice::F5::Device.new(Facter.value(:url))
    else
      @device ||= Puppet::Util::NetworkDevice.current
      raise Puppet::Error, "Puppet::Util::NetworkDevice::F5: device not initialized #{caller.join("\n")}" unless @device
    end

    @transport = @device.transport
  end

  def transport
    # this calls the class instance of self.transport instead of the object instance which causes an infinite loop.
    self.class.transport
  end

  def delete_file(filename)
    transport['System.ConfigSync'].delete_file(filename)
  end

  # The SOAP API have limits on transfer size, so we must process files in
  # chunks for download and upload.
  def download_file(filename)
    content = ''
    continue = true
    file_offset = 0
    # F5 recommended file processing chunk size.
    # http://devcentral.f5.com/Tutorials/TechTips/tabid/63/articleType/ArticleView/articleId/144/iControl-101--06--File-Transfer-APIs.aspx
    chunk_size = (64*1024)
    while (continue)
      chunk = transport['System.ConfigSync'].download_file(filename, chunk_size, file_offset).first

      content     += chunk.file_data
      file_offset += chunk_size

      continue = false if (chunk.chain_type == 'FILE_LAST') || (chunk.chain_type == 'FILE_FIRST_AND_LAST')
    end

    Base64.decode(content)
  end

  def upload_file(filename, content)
    continue = true
    chain_type = 'FILE_FIRST'
    file_offset = 0
    continue = true
    chunk_size = (64*1024)

    while (continue)
      if content.size <= chunk_size
        continue = false
        if file_offset == 0
          chain_type = 'FILE_FIRST_AND_LAST'
        else
          chain_type = 'FILE_LAST'
        end
      end

      chunk = Base64.encode(content[0..chunk_size-1])
      transport['System.ConfigSync'].upload_file(filename, { :file_data => chunk, :chain_type => chain_type })

      file_offset += chunk_size
      chain_type = 'FILE_MIDDLE'
      content = content[chunk_size..content.size]
    end
  end
  
  # Often we can't predict what a response will be (single value or list) so
  # we wrap it in a list, if it's not, to make life simpler.
  def self.arraywrap(arg)
    if !arg.is_a?(Array)
      [arg]
    else
      arg
    end
  end

  def arraywrap(arg)
    self.class.arraywrap(arg)
  end

  def self.debug(msg)
    Puppet.debug("(#{self.name}): #{msg}")
  end

  def debug(msg)
    self.class.debug(msg)
  end

  def self.set_activefolder(folder)
    self.device.active_folder = folder
  end

  def set_activefolder(folder)
    self.class.set_activefolder(folder)
  end

  def self.enable_recursive_query
    self.device.recursive_query_state = true
  end

  def start_transaction
    transport['System.Session'].call(:start_transaction)
  end

  def submit_transaction
    transport['System.Session'].call(:submit_transaction)
  end

  def rollback_transaction
    transport['System.Session'].call(:rollback_transaction)
  end
end

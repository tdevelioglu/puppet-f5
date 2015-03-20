## This code is simply the icontrol gem renamed and mashed up.
require 'openssl'
require 'savon'

module Savon
  class Client
    def get(call, message=nil, response_parser=nil)
      if message
        call_options = { message: message, response_parser: response_parser }
        reply = self.call(call, call_options).body["#{call}_response".to_sym]
      else
        call_options = { response_parser: response_parser }
        reply = self.call(call, call_options).body["#{call}_response".to_sym]
      end

      # Attempt to divine the appropriate repsonse from the reply message.
      # What we're looking for here is a {:return => nil} which we can get
      # from Savon 2.4.0.  If we get that just skip to returning a blank
      # hash and we move on.
      Puppet.debug("(F5 transport): Got #{reply[:return].class} as response to #{call}")
      if reply[:return] == nil
        return {}
      # Almost everything in Savon comes back as a hash, except SOMETIMES
      # in SNMP it doesn't.  WHAT?
      elsif reply[:return].is_a?(String) or reply[:return].is_a?(Array)
        return reply[:return]
      elsif reply[:return].has_key?(:item)
        response = reply[:return][:item]
        Puppet.debug("(F5 transport): Response has :item key with #{response.class} value")
      else
        response = reply[:return]
        Puppet.debug("(F5 transport): Response has no :item key. Returning #{response.class}")
      end


      # Here we handle nested hashes, which can be a pain in Savon.
      return response if response.is_a?(String) or response.is_a?(Array)
      if response.is_a?(Hash)
        if response[:item]
          Puppet.debug("(F5 transport): Found nested :item key with #{response[:item].class} value")
          return response[:item]
        else
          Puppet.debug("(F5 transport): Returning #{response.class}")
          return response
        end
      end
      return {}
    end
  end
end

module Puppet::Util::NetworkDevice::F5
  class Transport
    attr_reader :hostname, :username, :password, :directory
    attr_accessor :wsdls, :endpoint, :interfaces


    def initialize hostname, username, password, wsdls = []
      @hostname = hostname
      @username = username
      @password = password
      @directory = File.join(File.dirname(__FILE__), '..', 'wsdl')
      @wsdls = wsdls
      @endpoint = '/iControl/iControlPortal.cgi'
      @interfaces = {}

      @sessionid = get_interface('System.Session').get(:get_session_identifier)
      Puppet.debug("Got sessionid: #{@sessionid}")
    end

    def get_interfaces
      @wsdls.each do |wsdl|
        @interfaces[wsdl] = get_interface(wsdl)
      end

      @interfaces
    end

    def get_interface(wsdl)
        # We use + here to ensure no / between wsdl and .wsdl
        wsdl_path = File.join(@directory, wsdl + '.wsdl')

        http_headers = @sessionid.nil? ? {} : { 'X-iControl-Session' => @sessionid  }
        Puppet.debug("My http headers are: #{http_headers}")
        if File.exists? wsdl_path
          namespace = 'urn:iControl:' + wsdl.gsub(/(.*)\.(.*)/, '\1/\2')
          url = 'https://' + @hostname + '/' + @endpoint
          @interfaces[wsdl] = Savon.client(wsdl: wsdl_path, ssl_verify_mode: :none,
            basic_auth: [@username, @password], endpoint: url,
            namespace: namespace, convert_request_keys_to: :none,
            strip_namespaces: true, log: false, headers: http_headers,
            :convert_attributes_to => lambda {|k,v| []})
        end
    end

    def get_all_interfaces
      @wsdls = self.available_wsdls
      puts @wsdls
      self.get_interfaces
    end

    def available_interfaces
      @interfaces.keys.sort
    end

    def available_wsdls
      Dir.entries(@directory).delete_if {|file| !file.end_with? '.wsdl'}.sort
    end
  end
end

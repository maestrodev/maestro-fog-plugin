require 'maestro_agent'
require 'fog_worker'
require 'fog'
require 'fog/compute/models/server'

module Fog
  module Compute
    class Joyent

      # Add missing fields necessary for ssh
      # Taken from AWS Server
      class Server < Fog::Compute::Server

        attribute :public_ip_address
        attr_writer   :private_key, :private_key_path, :username

        # address used for ssh
        def public_ip_address
          ips.empty? ? nil : ips.first
        end

        def username
          @username ||= 'root'
        end

        def private_key_path
          @private_key_path ||= Fog.credentials[:private_key_path]
          @private_key_path &&= File.expand_path(@private_key_path)
        end

        def private_key
          @private_key ||= private_key_path && File.read(private_key_path)
        end
      end
    end
  end
end

module MaestroDev
  class JoyentWorker < FogWorker

    def provider
      "joyent"
    end

    def required_fields
      ['username', 'password', 'url']
    end

    def connect_options
      opts = {
          :joyent_username => get_field('username'),
          :joyent_password => get_field('password'),
          :joyent_url => get_field('url')
      }
      return opts
    end

    def create_server(connection, name)
      # InstantServers SSL certificate is not valid, disable verification
      Excon.defaults[:ssl_verify_peer] = false

      package = get_field('package')
      dataset = get_field('dataset')

      name_msg = name.nil? ? "" : "'#{name}' "
      package_msg = package.nil? ? "default" : package
      dataset_msg = dataset.nil? ? "default" : dataset
      msg = "Creating server #{name_msg}from package '#{package_msg}' and dataset '#{dataset_msg}'"
      Maestro.log.info msg
      write_output("#{msg}\n")

      begin
        options = {
          :package => package,
          :dataset => dataset,
          :name => name
        }
        s = connection.servers.create(options)
      rescue Excon::Errors::Error => e
        error = JSON.parse e.response.body
        msg = "Error #{msg}: #{error['code']} #{error['message']}"
        Maestro.log.error msg
        set_error msg
        return
      rescue Exception => e
        log("Error #{msg}", e) and return
      end
      return s
    end
  end
end

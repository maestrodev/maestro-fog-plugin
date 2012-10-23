require 'maestro_agent'
require 'fog_worker'
require 'fog'
require 'fog/compute/models/server'

module Fog
  module Compute
    class Vsphere

      # Add missing fields necessary for ssh
      # Taken from AWS Server
      class Server < Fog::Compute::Server
        attribute :public_ip_address,     :aliases => 'ipAddress'
        attr_writer   :private_key, :private_key_path, :username

        # address used for ssh
        def public_ip_address
          ipaddress
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

        def destroy(options = {})
          requires :instance_uuid
          stop if ready? # turn off before destroying
          connection.vm_destroy('instance_uuid' => instance_uuid)
        end
      end
    end
  end
end


module MaestroDev
  class VSphereWorker < FogWorker

    def provider
      "vsphere"
    end

    def required_fields
      ['host', 'datacenter', 'username', 'password', 'template_name']
    end

    def connect_options
      {
        :vsphere_server   => get_field('host'),
        :vsphere_username => get_field('username'),
        :vsphere_password => get_field('password')
      }
    end

    def name_split_char
      "_"
    end

    def create_server(connection, name)
      datacenter = get_field('datacenter')
      template_name = get_field('template_name')

      name = random_name if name.nil? || name.empty?

      msg = "Cloning VM #{template_name} into #{name}"
      Maestro.log.info msg
      write_output("#{msg}\n")

      path = "/Datacenters/#{datacenter}/#{template_name}"
      begin
        # easier to do vm_clone than find the server and then clone
        cloned = connection.vm_clone(
          'name' => name,
          'path' => path,
          'poweron' => true,
          'wait' => false)
      rescue Fog::Errors::NotFound => e
        msg = "VM template '#{path}' not found"
        Maestro.log.error msg
        set_error msg
        return
      rescue Exception => e
        log("Error cloning template '#{path}' as '#{name}'", e)
        return
      end
      s = connection.servers.get(cloned['vm_ref'])

      if s.nil?
        msg = "Failed to clone VM '#{path}' as '#{name}'"
        Maestro.log.error msg
        set_error msg
        return
      end
      return s
    end
  end

end

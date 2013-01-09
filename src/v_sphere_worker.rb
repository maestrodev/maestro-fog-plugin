require 'maestro_agent'
require 'fog_worker'
require 'fog'
require 'fog/compute/models/server'

module Fog
  module Compute
    class Vsphere
      class Server < Fog::Compute::Server
        def public_ip_address
          ipaddress
        end
        def state
          power_state
        end
        def image_id
          path
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
      ['host', 'username', 'password', 'template_path']
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
      template_path = get_field('template_path')
      dest_folder = get_field('destination_folder')
      datastore = get_field('datastore')
      full_dest_path = (dest_folder.nil? or dest_folder.empty?) ? name : "#{dest_folder}/#{name}"

      msg = "Cloning VM #{template_path} into #{full_dest_path}"
      Maestro.log.info msg
      write_output("#{msg}\n")

      options = {
        'name' => name,
        'path' => template_path,
        'poweron' => true,
        'wait' => false
      }

      if dest_folder && !dest_folder.empty?
        options.merge('dest_folder' => dest_folder)
      end
      if datastore && !datastore.empty?
        options.merge('datastore' => datastore)
      end

      begin
        # easier to do vm_clone than find the server and then clone
        cloned = connection.vm_clone(options)
      rescue Fog::Errors::NotFound => e
        msg = "VM template '#{template_path}' not found"
        Maestro.log.error msg
        set_error msg
        return
      rescue Exception => e
        log("Error cloning template '#{template_path}' as '#{full_dest_path}'", e)
        return
      end
      s = connection.servers.get(cloned['vm_ref'])

      if s.nil?
        msg = "Failed to clone VM '#{template_path}' as '#{full_dest_path}'"
        Maestro.log.error msg
        set_error msg
        return
      end
      return s
    end
  end

end

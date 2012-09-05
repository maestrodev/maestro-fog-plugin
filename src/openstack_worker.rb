require 'maestro_agent'
require 'fog_worker'
require 'fog'

module MaestroDev
  class OpenstackWorker < FogWorker

    def provider
      "openstack"
    end

    def required_fields
      ['username', 'api_key', 'tenant', 'auth_url', 'image_id', 'flavor_id']
    end

    def connect_options
      opts = {
          :openstack_auth_url => get_field('auth_url'),
          :openstack_tenant => get_field('tenant'),
          :openstack_username => get_field('username'),
          :openstack_api_key => get_field('api_key')
      }
      return opts
    end

    def create_server(connection, number_of_vms, i)
      image_id = get_field('image_id')
      flavor_id = get_field('flavor_id')
      base_name = get_field('name')
      key_name = get_field('key_name')
      tenant_id = get_field('tenant')
      security_group = get_field('security_group')

      if !base_name.nil? && !base_name.empty?
        name = number_of_vms > 1 ? "#{base_name}-#{i}" : base_name
      end
      ssh_user = get_field('ssh_user') || "root"

      msg = "Creating server '#{name}' from image #{image_id}"
      Maestro.log.info msg
      write_output("#{msg}\n")

      begin
        options = {
          :image_ref => image_id,
          :name => name,
          :flavor_ref => flavor_id,
          :key_name => key_name,
          :security_group => security_group,
          :tenant_id => tenant_id
        }
        s = connection.servers.create(options)
        s.wait_for { ready? }
      rescue Fog::Errors::NotFound => e
        msg = "Image id '#{image_id}', flavor '#{flavor_id}' not found"
        Maestro.log.error msg
        set_error msg
        return
      rescue Exception => e
        log("Error creating server from image #{image_id}", e) and return
      end
      return s
    end
  end
end

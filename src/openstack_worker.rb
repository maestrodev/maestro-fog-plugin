require 'maestro_agent'
require 'fog_worker'
require 'fog'
require 'fog/compute/models/server'

module Fog
  module Compute
    class OpenStack
      class Server < Fog::Compute::Server
        def error?
          state == 'ERROR'
        end
      end
    end
  end
end


module MaestroDev
  class OpenstackWorker < FogWorker

    def provider
      "openstack"
    end

    def required_fields
      ['auth_url', 'tenant', 'username', 'api_key', 'image_id', 'flavor_id']
    end

    def connect_options
      opts = {
          :openstack_auth_url => get_field('auth_url'),
          :openstack_tenant => get_field('tenant'),
          :openstack_username => get_field('username'),
          :openstack_api_key => get_field('api_key'),
          :openstack_region => get_field('region')
      }
      return opts
    end

    def create_server(connection, name)
      image_id = get_field('image_id')
      flavor_id = get_field('flavor_id')
      key_name = get_field('key_name')
      tenant_id = get_field('tenant')
      security_group = get_field('security_group')

      ssh_user = get_field('ssh_user') || "root"
      public_key = get_field('public_key')
      public_key_path = get_field('public_key_path')
      if (public_key && public_key_path) 
        write_output("WARNING: public_key_path is ignored because public_key is defined\n")
      end

      msg = "Creating server '#{name}' from image #{image_id}"
      Maestro.log.info msg
      write_output("#{msg}\n")

      begin
        options = {
          :image_ref => image_id,
          :name => name,
          :flavor_ref => flavor_id,
          :key_name => key_name,
          :username => ssh_user,
          :public_key => public_key,
          :public_key_path => public_key_path,
          :security_group => security_group,
          :tenant_id => tenant_id
        }
        s = connection.servers.create(options)
      rescue Fog::Errors::NotFound => e
        msg = "Image id '#{image_id}', flavor '#{flavor_id}' not found"
        Maestro.log.error msg
        set_error msg
        return
      rescue Fog::OpenStack::Errors::ServiceError => e
        msg = "Error creating server: #{e.message}"
        Maestro.log.error msg
        set_error msg
        return
      rescue Exception => e
        log("Error creating server from image #{image_id}", e) and return
      end
      return s
    end

    # copy the public key to the server
    def setup_server(s)
      unless s.public_key.nil? || s.public_key.empty?
        s.setup(:password => s.password)
      end
    end
  end
end

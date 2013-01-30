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
        def image_id
          image_ref
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
        error = e.message
        # TODO not needed in fog 1.8+
        if e.response_data && e.response_data.values && e.response_data.values.first
          error = "#{e.message} #{e.response_data.values.first['message']}"
        end
        # end TODO
        msg = "Error creating server: #{error}"
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

    def private_address(s)
      private_addr = ''
      if s.respond_to?(:attributes) && s.attributes && (s.attributes.is_a? Hash) && s.attributes[:addresses]
        # This is to handle how OpenStack (Folsom) returns address information.
        # On certain systems, only the private address is returned and is labelled
        # novanetwork. Not certain if it's like that on all OpenStack systems.
        private_addr = s.attributes[:addresses].values[0][0]['addr'] unless s.attributes[:addresses].empty?
      elsif s.respond_to?('addresses') && s.addresses && (s.addresses.is_a? Hash) && s.addresses["private"]
        private_addr = s.addresses["private"][0]["addr"]
      elsif s.respond_to?('private_ip_address') && s.private_ip_address
        private_addr = s.private_ip_address
      end
      private_addr
    end
  end
end

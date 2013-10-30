require 'maestro_plugin'
require 'fog_worker'
require 'fog'
require 'fog/compute/models/server'

module Fog
  module Compute
    class RackspaceV2
      class Server < Fog::Compute::Server
        def error?
          state == ERROR
        end
      end
    end
  end
end


module MaestroDev
  module Plugin
    class RackspaceWorker < FogWorker
  
      def provider
        "rackspace"
      end
  
      def required_fields
        ['username', 'api_key']
      end
  
      def connect_options
        version = get_field('version')
        version = version.to_s.downcase.to_sym unless version.nil?
  
        opts = {
          :rackspace_username => get_field('username'),
          :rackspace_api_key  => get_field('api_key'),
          :rackspace_region => get_field('region'),
          :version => version
        }
        auth_url = get_field('auth_url')
        opts.merge!({:rackspace_auth_url => auth_url}) if !auth_url.nil? && !auth_url.empty?

        compute_url = get_field('endpoint')
        opts.merge!({:rackspace_compute_url => compute_url}) if compute_url and !compute_url.empty? and version == :v2
        return opts
      end
  
      def create_server(connection, name, options={})
        image_id = get_field('image_id')
        flavor_id = get_field('flavor_id')
  
        public_key = get_field('public_key')
        public_key_path = get_field('public_key_path')
        if (public_key && public_key_path) 
          write_output("WARNING: public_key_path is ignored because public_key is defined\n")
        end
  
        msg = "Creating server '#{name}' from image #{image_id}"
        Maestro.log.info msg
        write_output("#{msg}\n")
  
        begin
          attributes = {
            :name => name,
            :image_id => image_id,
            :flavor_id => flavor_id,
            :username => options[:username],
            :public_key => public_key,
            :public_key_path => public_key_path
          }
          s = do_create_server(connection, attributes)
  
        rescue Fog::Errors::NotFound => e
          msg = "Image id '#{image_id}', flavor '#{flavor_id}' not found"
          Maestro.log.error msg
          set_error msg
          return
        rescue Fog::Rackspace::Errors::ServiceError => e
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
    end
  end
end

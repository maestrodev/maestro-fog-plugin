require 'maestro_plugin'
require 'fog_worker'
require 'fog'
require 'fog/compute/models/server'

module Fog
  module Compute
    class AWS
      class Server < Fog::Compute::Server
        def name
          tags['Name']
        end
      end
    end
  end
end

module MaestroDev
  module Plugin
    class AwsWorker < FogWorker
  
      def provider
        "aws"
      end
  
      def required_fields
        ['access_key_id', 'secret_access_key', 'image_id', 'flavor_id']
      end
  
      def connect_options
        opts = {
            :aws_access_key_id => get_field('access_key_id'),
            :aws_secret_access_key => get_field('secret_access_key'),
            :region => get_field('region') || 'us-east-1'
        }
        return opts
      end
  
      def create_server(connection, name, options={})
        availability_zone = get_field('availability_zone')
        image_id = get_field('image_id')
        flavor_id = get_field('flavor_id')
  
        msg = "Creating server '#{name}' from image #{image_id}"
        Maestro.log.info msg
        write_output("#{msg}\n")
  
        begin
          options = {
            :tags => { 'Name' => name },
            :availability_zone => get_field('availability_zone'),
            :image_id => image_id,
            :flavor_id => flavor_id,
            :key_name => get_field('key_name'),
            :groups => get_field('groups'),
            :user_data => get_field('user_data')
          }
          s = do_create_server(connection, options)
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
end

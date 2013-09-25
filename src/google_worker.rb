require 'maestro_plugin'
require 'fog_worker'
require 'fog'
require 'fog/compute/models/server'

module Fog
  module Compute
    class Google
      class Server < Fog::Compute::Server
        def image_id
          image_name
        end
      end
    end
  end
end

module MaestroDev
  module FogPlugin
    class GoogleWorker < FogWorker
  
      def provider
        "google"
      end
  
      def required_fields
        ['project', 'client_email', 'key_location']
      end
  
      def connect_options
        key_location = File.expand_path(get_field('key_location'))
        raise MaestroDev::Plugin::ConfigError, "Key location not found: #{key_location}" unless File.exist? key_location
        {
          :google_project => get_field('project'),
          :google_client_email => get_field('client_email'),
          :google_key_location => key_location
        }
      end
  
      def create_server(connection, name)
        image_name = get_field('image_name', "centos-6-v20130813")
        machine_type = get_field('machine_type', "n1-standard-1")
        zone_name = get_field('zone_name', "us-central1-a")
        public_key = get_field('public_key')
        public_key_path = get_field('public_key_path')
        if (public_key && public_key_path) 
          write_output("WARNING: public_key_path is ignored because public_key is defined\n")
        end
        ssh_user = get_field('ssh_user', 'maestro')
        write_output("WARNING: Google images have root ssh disabled by default\n") if ssh_user == "root"

        name_msg = name.nil? ? "" : "'#{name}' "
        log_output("Creating server #{name_msg}from image #{image_name}/#{machine_type} in #{zone_name}", :info)
  
        options = {
          :name => name,
          :image_name => image_name,
          :machine_type => machine_type,
          :zone_name => zone_name,
          :public_key => public_key,
          :public_key_path => public_key_path,
          :username => ssh_user
        }

        begin
          s = do_create_server(connection, options)
        rescue Exception => e
          log("Error creating server with options: #{options.to_json}", e) and return
        end
        return s
      end
    end
  end
end

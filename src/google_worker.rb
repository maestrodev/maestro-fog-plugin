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
  module Plugin
    class GoogleWorker < FogWorker
  
      def provider
        "google"
      end
  
      def required_fields
        ['project', 'client_email', 'key_location']
      end
  
      def connect_options
        key_location = File.expand_path(get_field('key_location'))
        raise ConfigError, "Key location not found: #{key_location}" unless File.exist? key_location
        {
          :google_project => get_field('project'),
          :google_client_email => get_field('client_email'),
          :google_key_location => key_location
        }
      end
  
      def create_server(connection, name, options={})
        image_name = get_field('image_name', "centos-6-v20130813")
        machine_type = get_field('machine_type', "n1-standard-1")
        zone_name = get_field('zone_name', "us-central1-a")
        disk_size = get_int_field('disk_size', 10)
        public_key = get_field('public_key')
        public_key_path = get_field('public_key_path')
        if (public_key && public_key_path) 
          write_output("WARNING: public_key_path is ignored because public_key is defined\n")
        end
        write_output("WARNING: Google images have root ssh disabled by default\n") if options[:username] == "root"

        name_msg = name.nil? ? "" : "'#{name}' "
        log_output("Creating server #{name_msg}from image #{image_name}/#{machine_type} in #{zone_name}", :info)

        options = {
          :name => name,
          :machine_type => machine_type,
          :zone_name => zone_name,
          :tags => get_field('tags'),
          :public_key => public_key,
          :public_key_path => public_key_path,
          :username => options[:username]
        }

        # create persistent disk
        msg = "Creating disk '#{name}' and waiting for it to be ready"
        Maestro.log.debug msg
        write_output("#{msg}...")
        start = Time.now

        disk = connection.disks.create({
          :name => name,
          :size_gb => disk_size,
          :zone_name => zone_name,
          :source_image => image_name,
        })

        disk.wait_for { disk.ready? }
        Maestro.log.debug "Disk '#{name}' is ready (#{Time.now - start}s)"
        write_output("done (#{Time.now - start}s)\n")

        options[:disks] = [disk]

        begin
          s = do_create_server(connection, options)
        rescue Exception => e
          log("Error creating server with options: #{options.to_json}", e) and return
        end
        return s
      end

      # destroy the server object
      def destroy_server(connection, server)
        disks = server.disks.select{|d| d["type"] == "PERSISTENT"}
        server.destroy
        destroy_disks = get_boolean_field('destroy_disks')
        if destroy_disks
          return if disks.empty?

          # We need to wait for instance to be terminated before destroying disks
          start = Time.now
          msg = "Waiting for server to be terminated: #{server.name}"
          Maestro.log.debug(msg)
          write_output("#{msg}...")
          begin
            server.wait_for { state == "TERMINATED" }
          rescue Fog::Errors::NotFound => e
            # if server is terminated we may get a NotFound error
          end
          Maestro.log.debug("Server is terminated: #{server.name} (#{Time.now - start}s)")
          write_output("done (#{Time.now - start}s)\n")

          # Delete the disks
          start = Time.now
          disks_to_delete = []
          disks.each do |d|
            match = d["source"].match(%r{projects/(.*)/zones/(.*)/disks/(.*)})
            disks_to_delete << {:project => match[1], :zone => match[2], :disk => match[3]}
          end

          msg = "Deleting disks: #{disks_to_delete.map{|d| d[:disk]}}"
          Maestro.log.debug(msg)
          write_output("#{msg}...")

          disks_to_delete.each do |d|
            disk = connection.disks.get(d[:disk],d[:zone])
            disk.destroy
          end

          Maestro.log.debug("Deleted disks: #{disks_to_delete.map{|d| d[:disk]}} (#{Time.now - start}s)")
          write_output("done (#{Time.now - start}s)\n")
        end
      end
    end
  end
end

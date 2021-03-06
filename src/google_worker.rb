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

      TAG_REGEX = /(?:[a-z](?:[-a-z0-9]{0,61}[a-z0-9])?)/

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
  
      def server_exists?(connection, name)
        begin
          !connection.servers.get(name, get_field('zone_name')).nil?
        rescue Fog::Errors::NotFound # needed in fog <=1.19.0
          false
        end
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
        service_account_email = get_field('service_account_email')
        service_account_scopes = get_field('service_account_scopes')
        # remove any empty values
        service_account_scopes.reject! { |s| s.nil? or s.empty? } if service_account_scopes
        if (service_account_scopes.nil? || service_account_scopes.empty?)
          if service_account_email
            write_output("WARNING: no service account will be created for the supplied email as no scopes were provided")
          end

          service_accounts = nil
        else
          unless service_account_email
            # 123845678986-abcdefghijk@developer.gserviceaccount.com -> 123845678986@project.gserviceaccount.com
            service_account_email = get_field('client_email').gsub(/(.*)-(.*)@developer/, '\1@project')
          end

          service_accounts = [
              :email => service_account_email,
              :scopes => service_account_scopes
          ]
        end

        name_msg = name.nil? ? "" : "'#{name}' "
        log_output("Creating server #{name_msg}from image #{image_name}/#{machine_type} in #{zone_name}", :info)
        log_output("Adding service account #{service_accounts}") if service_accounts

        options = {
          :name => name,
          :machine_type => machine_type,
          :zone_name => zone_name,
          :tags => sanitize_tags(get_field('tags')),
          :public_key => public_key,
          :public_key_path => public_key_path,
          :username => options[:username],
          :service_accounts => service_accounts
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

          # we need to wait until the server is removed from GCE
          # state == TERMINATED doesn't let us delete the disk yet
          begin
            server.wait_for { false }
          rescue Fog::Errors::NotFound => e
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

      private

      def sanitize_tags(tags)
        return nil if tags.nil?
        tags.map {|tag| (m = tag.match(TAG_REGEX)) && m[0]}.compact
      end
    end
  end
end

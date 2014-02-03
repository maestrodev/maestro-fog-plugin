require 'maestro_plugin'
require 'fog'
require 'fog/core/model'

module Fog
  module Compute
    class Server < Fog::Model
      def error?
        false
      end
    end
  end
end

module MaestroDev
  module Plugin
    class FogWorker < Maestro::MaestroWorker
  
      SERVERS_CONTEXT_OUTPUT_KEY = 'servers'
  
      def log(message, exception)
        msg = "#{message}: #{exception.class} #{exception.message}\n#{exception.backtrace.join("\n")}"
        Maestro.log.error msg
        set_error(msg)
      end
  
      def log_output(msg, level=:debug)
        Maestro.log.send(level, msg)
        write_output "#{msg}\n"
      end
  
      def required_fields
        []
      end
  
      def validate_provision_fields
        missing_fields = []
        required_fields.each{|s|
          missing_fields << s if get_field(s).nil? || get_field(s).empty?
        }
        raise ConfigError, "Missing fields: #{missing_fields.join(", ")}" unless missing_fields.empty?
      end
  
      def provider
        raise "Need to extend provider method!"
      end
  
      def connect_options
        raise "Need to extend connect_options method!"
      end
  
      # create and return the server object. Don't wait for it to be ready
      def create_server(connection, name, options={})
        raise "Need to extend create_server method!"
      end
  
      # destroy the server object
      def destroy_server(connection, server)
        server.destroy
      end
  
      # configure public keys if needed when server is up
      def setup_server(s)
        # noop
      end

      # Check if there's already a server with this name
      def server_exists?(connection, name)
        connection.servers.any? {|s| s.name == name}
      end

      # connect to the provider
      def connect(overwrite_from_fields = false)
        msg = "Connecting to #{provider}"
        Maestro.log.info msg
        write_output "#{msg}..."

        opts = connect_options
        # used for deprovision, get the fields set by the provision task
        # the field names could have been overwritten by other tasks
        if overwrite_from_fields
          opts.each do |k,v|
            field_value = get_field(k.to_s)
            opts[k] = field_value if field_value
          end
        end
        opts.each { |k,v| set_field(k.to_s, v) }

        start = Time.now
        connection = Fog::Compute.new(opts.merge(:provider => provider))

        Maestro.log.debug "Connected to #{provider} (#{Time.now - start}s)"
        write_output("done (#{Time.now - start}s)\n")
        return connection
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
        raise PluginError, "Unable to connect to #{provider}: #{e}"
      end
  
      # character to use to split names with random_name
      def name_split_char
        "-"
      end
  
      # create 5 random chars if name not provided
      # if it's a fully qualified domain add them to the host name only
      def random_name(basename = "maestro")
        parts = (basename.nil? or basename.empty? ? "maestro" : basename).split(".")
        parts[0]="#{parts[0]}#{name_split_char}#{(0...5).map{ ('a'..'z').to_a[rand(26)] }.join}"
        parts.join(".")
      end
  
      # execute when server is ready
      def on_ready(s, commands)
        create_server_on_master(s)
  
        wait_for_public_ip = get_field('wait_for_public_ip')

        start = Time.now
        unless wait_for_public_ip == false
          msg = "Waiting for server '#{s.name}' #{s.identity} to get a public ip"
          Maestro.log.debug msg
          write_output("#{msg}... ")
  
          begin
            s.wait_for { !public_ip_address.nil? and !public_ip_address.empty? }
          rescue Fog::Errors::TimeoutError => e
            msg = "Server '#{s.name}' #{s.identity} failed to get a public ip (#{Time.now - start}s)"
            Maestro.log.warn msg
            write_output("failed (#{Time.now - start}s)\n")
            return nil
          end
        end
  
        Maestro.log.debug "Server '#{s.name}' #{s.identity} is now accessible through ssh (#{Time.now - start}s)"
        write_output("done (#{Time.now - start}s)\n")
  
        # save some values in the workitem so they are accessible for deprovision and other tasks
        populate_meta([s], 'new')
        save_server_in_context([s])
  
        log_output("Server '#{s.name}' #{s.identity} started with public ip '#{s.public_ip_address}' and private ip '#{private_address(s)}'", :info)
  
        start = Time.now
        msg = "Initial setup for server '#{s.name}' #{s.identity} on '#{s.public_ip_address}'"
        Maestro.log.debug msg
        write_output("#{msg}...")
        begin
          setup_server(s)
          Maestro.log.debug "Finished initial setup for server '#{s.name}' #{s.identity} on '#{s.public_ip_address}' (#{Time.now - start}s)"
          write_output("done (#{Time.now - start}s)\n")
        rescue Net::SSH::AuthenticationFailed => e
          log_output("Failed to setup server '#{s.name}' #{s.identity} on '#{s.public_ip_address}' (#{Time.now - start}s). Authentication failed for user '#{s.username}'")
          return nil
        end
  
        # provision through ssh
        start = Time.now
        server_errors = provision_execute(s, commands)
        unless server_errors.empty?
          log_output("Server '#{s.name}' #{s.identity} failed to provision", :info)
          write_output(server_errors.join("\n"))
          return nil
        end
        log_output("Server '#{s.name}' #{s.identity} ssh provisioned in #{Time.now-start}s", :info)
  
        return s
      end
  
      def private_address(s)
        private_addr = ''
        if s.respond_to?('addresses') && s.addresses && (s.addresses.is_a? Hash) && s.addresses["private"]
          private_addr = s.addresses["private"][0]["addr"]
        elsif s.respond_to?('private_ip_address') && s.private_ip_address
          private_addr = s.private_ip_address
        end
        private_addr
      end
  
      # returns an array with errors, or empty if successful
      def provision_execute(s, commands)
        errors = []
        return errors if (commands.nil? or commands.empty?)
  
        if (!get_field("cloud_ips").nil? and !get_field("cloud_ips").empty?)
          host = get_field("cloud_ips")[0]
        elsif (!get_field("cloud_private_ips").nil? and !get_field("cloud_private_ips").empty?)
          host = get_field("cloud_private_ips")[0]
        else
          msg = "No IP address associated to the machine #{host} - cannot run SSH command"
          errors << msg
          log_output(msg, :info)
          return errors
        end
  
        ssh_password = get_field('ssh_password')
        ssh_options = {}
        msg = "Running SSH Commands On New Machine #{s.username}@#{host}"
        msg_options = {}
        if (ssh_password and !ssh_password.empty?)
          ssh_options[:password] = ssh_password
          msg_options[:password] = "*" * ssh_password.size
        end
        msg_options[:private_key_path] = s.private_key_path if s.private_key_path
        msg_options[:private_key] = mask_private_key(s.private_key.strip) if s.private_key # show only last 5 chars
        log_output("#{msg} using #{msg_options}: #{commands.join(", ")}", :info)

        for i in 1..10
          begin
            log_output("[#{host}] Running Commands:\n  #{commands.join("\n  ")}\n")
            responses = s.ssh(commands, ssh_options) do |data, extended_data|
              write_output(data, :buffer => true) unless data.empty? #stdout
              write_output(extended_data, :buffer => true) unless extended_data.empty? #stderr
            end

            responses.each do |result|
              if result.status != 0
                msg = "[#{host}] Command '#{result.command}' failed with status #{result.status}"
                errors << msg
                log_output(msg, :info)
              end
            end unless responses.nil?
            break
          rescue Errno::EHOSTUNREACH, Timeout::Error, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::SSH::Disconnect => e
            log_output("[#{host}] Try #{i} - failed to connect: #{e}, retrying...", :info)
            if i+1 > 10
              msg = "[#{host}] Could not connect to remote machine after 10 attempts"
              errors << msg
              log_output(msg, :warn)
            else
              sleep 5
              next
            end
          rescue Net::SSH::AuthenticationFailed => e
            log_output("[#{host}] Try #{i} - failed to connect: authentication failed for user #{e.message}, retrying...", :info)
            if i+1 > 10
              msg = "[#{host}] Could not connect to remote machine after 10 attempts, authentication failed for user #{e.message}"
              errors << msg
              log_output(msg, :warn)
            else
              sleep 5
              next
            end
          end
        end
        return errors
      end
  
      def provision
        log_output("Starting #{provider} provision", :info)
        validate_provision_fields
        connection = connect
        servers = []
  
        number_of_vms = get_field('number_of_vms', 1)
  
        # validate ssh options early before starting vms
        commands = get_field('ssh_commands')
        username = get_field('ssh_user', "root")
        private_key = get_field("private_key")
        private_key_path = get_field("private_key_path")
        ssh_password = get_field("ssh_password")
  
        # when ssh commands are set
        if !(commands.nil? or commands.empty?)
          if private_key.nil? and private_key_path.nil? and ssh_password.nil?
            msg = "private_key, private_key_path or ssh_password are required for SSH"
            Maestro.log.info msg
            set_error msg
            return
          end
          if private_key_path
            private_key_path = File.expand_path(private_key_path)
            unless File.exist?(private_key_path)
              msg = "private_key_path does not exist: #{private_key_path}"
              Maestro.log.info msg
              set_error msg
              return
            end
          end
        end
  
        name = get_field('name', '')

        # some providers require name, so let's assign a random one if not set to be sure
        # guarantee unique name if name is specified but taken already or launching more than 1 vm
        randomize_name = (name.empty? or (number_of_vms > 1))

        unless randomize_name
          msg = "Looking for existing vms with name '#{name}'"
          start = Time.now
          Maestro.log.debug msg
          write_output "#{msg}..."
          randomize_name = server_exists?(connection, name)
          write_output "done (#{Time.now - start}s)\n"
        end
  
        # start the servers
        (1..number_of_vms).each do |i|
          server_name = randomize_name ? random_name(name) : name
  
          log_output("Creating server '#{server_name}'")
          start = Time.now
  
          # create the server in the cloud provider
          s = create_server(connection, server_name, {:username => username})

          if s.nil? && get_field("__error__").nil?
            log_output("Failed to create server '#{server_name}' (#{Time.now - start}s)", :error)
          end
          next if s.nil?

          populate_meta([s], 'new')
          log_output("Created server '#{s.name}' with id '#{s.identity}' (#{Time.now - start}s)", :info)
  
          s.username = username
          s.private_key = private_key
          s.private_key_path = private_key_path
          servers << s
        end
  
        save_server_ids_in_context(servers)
  
        # if there was an error provisioning servers, return
        return if !get_field("__error__").nil? and !get_field("__error__").empty?
  
        # wait for servers to be up and set them up
        servers_ready = []
        servers_provisioned = []
        start = Time.now
        last_log = start
        timeout = get_field('timeout') || Fog.timeout
        provisioning_time = 0
        while !servers.empty?
          now = Time.now
          server_names = servers.map{|s| s.name}.join(", ")
          duration = now - start - provisioning_time
          if duration > timeout
            log_output("Servers timed out (#{duration} seconds) before being ready: #{server_names}", :warn)
            break
          end
  
          # only print waiting message every 10 secs
          if now > last_log + 10
            log_output("Waiting #{(timeout - duration).to_i} seconds for servers to be ready: #{server_names}")
            last_log = now
          end

          servers.each { |s| s.reload }
          s = servers.find { |s| s.ready? or s.error? }
          if s.nil?
            sleep(1)
          else
            if s.error?
              state = s.respond_to?('state') ? " with state: #{s.state}" : ""
              Maestro.log.warn "Server '#{s.name}' #{s.identity} failed to start#{state} (#{Time.now - start}s)"
              write_output("failed#{state} (#{Time.now - start}s)\n")
              servers.delete(s)
            else
              log_output("Server '#{s.name}' #{s.identity} is ready (#{Time.now - start}s)")
              servers_ready << servers.delete(s)
              # wait for servers to have public ip and run commands. Don't add provisioning time to timeout
              provision_start = Time.now
              servers_provisioned << on_ready(s, commands)
              provisioning_time += Time.now - provision_start
            end
          end
        end
  
        if servers_ready.compact.empty?
          msg = "All servers failed to start"
          Maestro.log.warn msg
          set_error msg
          return
        end
  
        # check that not all the servers failed
        if servers_provisioned.compact.empty?
          msg = "All servers failed to provision"
          Maestro.log.warn msg
          set_error msg
          return
        end
  
        msg = "Maestro #{provider} provision complete!"
        Maestro.log.debug msg
        write_output("#{msg}\n")
      end
  
      # deprovision vms
      def deprovision
        log_output("Starting #{provider} deprovision", :info)
  
        # if instance ids are explicitly set in the task
        # ids can be an id or a name
        ids = get_field("instance_ids")
        # otherwise use the ids of instances started previously
        ids = get_field("#{provider}_ids") if ids.nil? or ids.empty?
  
        if ids.nil? or ids.empty?
          log_output("No servers found to be deprovisioned", :warn)
          return
        end
  
        connection = connect(true)
  
        ids.each do |id|
          log_output("Deprovisioning VM with id/name '#{id}'", :info)

          start = Time.now
          begin
            s = connection.servers.get(id) || connection.servers.find{|server| server_name(server) == id }
  
            if s.nil?
              Maestro.log.warn("VM with id/name '#{id}' not found, ignoring")
              write_output("not found, ignoring\n")
              # server was already destroyed in provider, delete anyway in master record by id
              # we don't want to delete in master by name as it is dangerous, a new vm could be started with same name
              delete_server_on_master(id)
            else
              destroy_server(connection, s)
              delete_server_on_master(s.identity)
              log_output("Deprovisioned VM with id/name '#{id}' (#{Time.now - start}s)", :info)
            end
          rescue Exception => e
            log("Error destroying instance with id/name '#{id}' (#{Time.now - start}s)", e)
          end
        end
  
        log_output("Maestro #{provider} deprovision complete!", :info)
      end

      # find servers in cloud provider
      def find
        log_output("Starting #{provider} find", :info)
        validate_provision_fields
        connection = connect
  
        name = get_field('name')
        # select those servers matching name. Fail if servers don't have a name
        servers = connection.servers.select do |s|
          if s.respond_to?(:name)
            s.name =~ /#{name}/
          else
            raise PluginError, "Provider #{provider} does not support finding servers by name"
          end
        end

        save_server_ids_in_context(servers, true)
        save_server_in_context(servers, true)
        populate_meta(servers, 'find', true)

        msg = servers.empty? ? "#{provider} found no servers" : "#{provider} found #{servers.size} servers: "
        msg += servers.map{|s| s.respond_to?(:name) ? s.name : s.identity}.join(",")
        Maestro.log.debug msg
        write_output("#{msg}\n")
      end

      # attributes tha can be updated in the provider' server
      def updatable_attributes
        [:name]
      end

      # update servers in cloud provider
      def update
        log_output("Starting #{provider} update", :info)
        validate_provision_fields
        connection = connect
  
        id = get_field('id') || (get_field("#{provider}_ids") || []).first
        raise ConfigError, "Missing fields: id" if id.nil?

        server = connection.servers.get(id)
        log_output("#{provider} updating server #{id}: #{server.nil? ? 'not found' : 'found' }")

        # attributes to update in the server
        new_attributes = {}
        updatable_attributes.each do |attribute|
          new_attributes[attribute] = get_field(attribute.to_s)
        end

        new_attributes.delete_if { |k, v| v.nil? or v.empty? }
        new_attributes.each do |k,v|
          if server.respond_to?(k)
            server.send("#{k}=",v)
          else
            raise PluginError, "Provider #{provider} does not support #{k} attribute"
          end
        end
        server.update unless new_attributes.empty?
        populate_meta([server], 'update')

        log_output("#{provider} server #{id} updated with: #{new_attributes}", :info)
      end
  
      # save the server data in the Maestro database
      def create_server_on_master(s)
        image_id = server_image_id(s)   #s.respond_to?('image_id') ? s.image_id : 'no_image'
        flavor_id = server_flavor_id(s) #s.respond_to?('flavor_id') ? s.flavor_id : nil
        create_record_with_fields("machine",
          ["name",         "type",   "instance_id", "public_ipv4",       "image_id", "flavor_id"],
          [server_name(s), provider, s.identity, s.public_ip_address, image_id  , flavor_id])
      end
  
      def delete_server_on_master(id)
        delete_record("machine", {"instance_id" => id, "type" => provider})
      end
  
      # Get server name, or its id if name not supported
      # Some servers will expose a name attribute, but will return id - its up to them whether they support a
      # human readable name
      def server_name(s)
        (s.respond_to?('name') && s.name) ? s.name : s.identity
      end
      
      # Get the image used to create a server
      def server_image_id(s)
        s.respond_to?('image_id') ? s.image_id : 'no_image'
      end
      
      # Get the flavor used to create a server, describing disk, ram, cpu,...
      def server_flavor_id(s)
        s.respond_to?('flavor_id') ? s.flavor_id : nil
      end


      # Helper methods that can only be called within this class/subclass - not exposed to external entitles
      # The main idea here is that we don't really want subclasses calling methods on the connection, by doing that
      # they bypass our ability to report info & metrics'y stuff
      private
  
      # Creates a new server
      def do_create_server(connection, options)
        server = connection.servers.create(options)
        yield(server) if block_given?
        server
      end
  
      def get_server_by_id(connection, id)
        connection.servers.get(id)
      end
  
      # populate the contex outputs with a server hash object
      # overwrite removes all previous servers from the context
      def populate_meta(servers, operation, overwrite=false)
        save_output_value('method', operation) if operation

        # Cannot use 'read_output_value' without ensuring the value is already set, otherwise it will
        # return the value from the previous run, so we will have to hack it until the read_output_value
        # method can take a "ignore_previous" type flag -- akk
        my_context_outputs = get_field('__context_outputs__') || {}
        context_servers = (overwrite ? nil : my_context_outputs[SERVERS_CONTEXT_OUTPUT_KEY]) || []
  
        servers.each do |server|
          raise ArgumentError, "Parameter is not a Fog::Compute::Server object, it is a #{server.class}" unless server.is_a?(Fog::Compute::Server)

          # delete if already exists
          context_servers.delete_if {|s| s['id'] == server.identity and s['provider'] == provider}

          server_meta_data = { 'id' => server.identity, 'name' => server_name(server), 'ip' => server.public_ip_address, 'image' => server_image_id(server), 'flavor' => server_flavor_id(server) , 'provider' => provider }
          ipv4 = server.public_ip_address
          server_meta_data['ipv4'] = ipv4 if ipv4
          context_servers << server_meta_data
        end
        save_output_value(SERVERS_CONTEXT_OUTPUT_KEY, context_servers)
      end

      # save server ids in context for deprovisioning or other tasks
      # overwrite removes all previous server ids from the context
      def save_server_ids_in_context(servers, overwrite=true)
        ids = servers.map {|s| s.identity}
        set_field("#{provider}_ids", ids.concat(get_field("#{provider}_ids") || []))
        set_field("cloud_ids", ids.concat(get_field("cloud_ids") || []))
      end

      # save server name, public and private ip address in context
      # overwrite removes all previous servers from the context
      def save_server_in_context(servers, overwrite=true)
        fields = ["#{provider}_private_ips", "cloud_private_ips", "#{provider}_ips", "cloud_ips", "#{provider}_names", "cloud_names"]
        values = {}
        fields.each {|f| values[f] = get_field(f) || []}

        servers.each do |s|
          private_addr = private_address(s)
          ip = s.public_ip_address
          name = server_name(s)

          if private_addr and !private_addr.empty?
            values["#{provider}_private_ips"] << private_addr
            values["cloud_private_ips"] << private_addr
          end

          unless s.public_ip_address.nil?
            values["#{provider}_ips"] << ip
            values["cloud_ips"] << ip
          end

          values["#{provider}_names"] << name
          values["cloud_names"] << name
        end

        values.each {|k,v| set_field(k, v)}
      end

      def mask_private_key(private_key)
        mask_end = [private_key.size-5,8].max # mask no less than 8 chars
        mask = private_key.size > 8 ? "..." : ("*" * 8)
        mask + (private_key[mask_end..-1] || "") # show only last 5 chars
      end

    end
  end
end

require 'maestro_agent'
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
      errors = []
      required_fields.each{|s|
        errors << "missing #{s}" if get_field(s).nil? || get_field(s).empty?
      }
      return errors
    end

    def provider
      raise "Need to extend provider method!"
    end

    def connect_options
      raise "Need to extend connect_options method!"
    end

    # create and return the server object. Don't wait for it to be ready
    def create_server(connection, name)
      raise "Need to extend create_server method!"
    end

    # configure public keys if needed when server is up
    def setup_server(s)
      # noop
    end

    def connect(overwrite_from_fields = false)
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
      Fog::Compute.new(opts.merge(:provider => provider))
    end

    # character to use to split names with random_name
    def name_split_char
      "-"
    end

    # create 5 random chars if name not provided
    # if it's a fully qualified domain add them to the host name only
    def random_name(basename = "maestro")
      basename ||= "maestro"
      parts = basename.split(".")
      parts[0]="#{parts[0]}#{name_split_char}#{(0...5).map{ ('a'..'z').to_a[rand(26)] }.join}"
      parts.join(".")
    end

    # execute when server is ready
    def on_ready(s, commands)
      create_server_on_master(s)

      wait_for_public_ip = get_field('wait_for_public_ip')

      unless wait_for_public_ip == false
        msg = "Waiting for server '#{s.name}' #{s.id} to get a public ip"
        Maestro.log.debug msg
        write_output("#{msg}... ")

        begin
          s.wait_for { !public_ip_address.nil? and !public_ip_address.empty? }
        rescue Fog::Errors::TimeoutError => e
          msg = "Server '#{s.name}' #{s.id} failed to get a public ip"
          Maestro.log.warn msg
          write_output("failed\n")
          return nil
        end
      end

      Maestro.log.debug "Server '#{s.name}' #{s.id} is now accessible through ssh"
      write_output("done\n")

      private_addr = private_address(s)

      if private_addr and !private_addr.empty?
        set_field("#{provider}_private_ips", (get_field("#{provider}_private_ips") || []) << private_addr)
        set_field("cloud_private_ips", (get_field("cloud_private_ips") || []) << private_addr)
      end

      # save some values in the workitem so they are accessible for deprovision and other tasks
      unless s.public_ip_address.nil?
        set_field("#{provider}_ips", (get_field("#{provider}_ips") || []) << s.public_ip_address)
        set_field("cloud_ips", (get_field("cloud_ips") || []) << s.public_ip_address)
      end
      set_field("#{provider}_names", (get_field("#{provider}_names") || []) << server_name(s))
      set_field("cloud_names", (get_field("cloud_names") || []) << server_name(s))

      log_output("Server '#{s.name}' #{s.id} started with public ip '#{s.public_ip_address}' and private ip '#{private_addr}'", :info)

      msg = "Initial setup for server '#{s.name}' #{s.id} on '#{s.public_ip_address}'"
      Maestro.log.debug msg
      write_output("#{msg}...")
      begin
        setup_server(s)
        Maestro.log.debug "Finished initial setup for server '#{s.name}' #{s.id} on '#{s.public_ip_address}'"
        write_output("done\n")
      rescue Net::SSH::AuthenticationFailed => e
        log_output("Failed to setup server '#{s.name}' #{s.id} on '#{s.public_ip_address}'. Authentication failed for user '#{s.username}'")
        return nil
      end

      # provision through ssh
      server_errors = provision_execute(s, commands)
      unless server_errors.empty?
        log_output("Server '#{s.name}' #{s.id} failed to provision", :info)
        write_output(server_errors.join("\n"))
        return nil
      end

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
      ssh_options[:password] = ssh_password if (ssh_password and !ssh_password.empty?)
      log_output("Running SSH Commands On New Machine #{host} - #{commands.join(", ")}", :info)

      for i in 1..10
        begin
          responses = s.ssh(commands, ssh_options)
          responses.each do |result|
            e = result.stderr
            o = result.stdout

            log_output("[#{host}] Ran Command #{result.command} With Output:\n#{o}\n")

            if !result.stderr.nil? && result.stderr != ''
              log_output("[#{host}] Stderr:\n#{o}")
            end

            if result.status != 0
              msg = "[#{host}] Command '#{result.command}' failed with status #{result.status}"
              errors << msg
              log_output(msg, :info)
            end

          end unless responses.nil?
          break
        rescue Errno::EHOSTUNREACH, Timeout::Error, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::SSH::Disconnect => e
          log_output("[#{host}] Try #{i} - failed to connect: #{e}, retrying...", :info)
          i = i+1
          if i > 10
            msg = "[#{host}] Could not connect to remote machine after 10 attempts"
            errors << msg
            log_output(msg, :warn)
          else
            sleep 5
            next
          end
        rescue Net::SSH::AuthenticationFailed => e
          msg = "[#{host}] Could not connect to remote machine, authentication failed for user #{e.message}"
          errors << msg
          log_output(msg, :warn)
        end
      end
      return errors
    end

    def provision
      log_output("Starting #{provider} provision", :info)

      errors = validate_provision_fields
      unless errors.empty?
        msg = "Not a valid fieldset, #{errors.join("\n")}"
        Maestro.log.error msg
        set_error msg
        return
      end

      begin
        msg = "Connecting to #{provider}"
        Maestro.log.info msg
        write_output "#{msg}..."
        connection = connect
        Maestro.log.debug "Connected to #{provider}"
        write_output("done\n")
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
        msg = "Unable to connect to #{provider}: #{e}"
        write_output("#{msg}\n")
        Maestro.log.error msg
        set_error msg
        return
      end

      servers = []

      number_of_vms = get_field('number_of_vms') || 1

      # validate ssh options early before starting vms
      commands = get_field('ssh_commands')
      username = get_field('ssh_user') || "root"
      private_key = get_field("private_key")
      private_key_path = get_field("private_key_path")
      ssh_password = get_field("ssh_password")

      # when ssh commands are set
      if !(commands.nil? or commands.empty?)
        if private_key.nil? and private_key_path.nil? and ssh_password.nil?
          msg = "private_key, private_key_path or ssh_password are required for SSH"
          Maestro.log.error msg
          set_error msg
          return
        end
        if private_key_path
          private_key_path = File.expand_path(private_key_path)
          unless File.exist?(private_key_path)
            msg = "private_key_path does not exist: #{private_key_path}"
            Maestro.log.error msg
            set_error msg
            return
          end
        end
      end

      name = get_field('name')
      if !name.nil? and number_of_vms==1
        msg = "Looking for existing vms with name '#{name}'"
        Maestro.log.debug msg
        write_output "#{msg}..."
        existing_names = connection.servers.map {|s| s.name}
        write_output "done\n"
      end
      # some providers require name, so let's assign a random one if not set to be sure
      # guarantee unique name if name is specified but taken already or launching more than 1 vm
      randomize_name = (name.nil? or name.empty? or (number_of_vms > 1) or existing_names.include?(name))

      # start the servers
      (1..number_of_vms).each do |i|
        server_name = randomize_name ? random_name(name) : name

        log_output("Creating server '#{server_name}'")

        # create the server in the cloud provider
        s = create_server(connection, server_name)

        if s.nil? && get_field("__error__").nil?
          log_output("Failed to create server '#{server_name}'", :error)
        end
        next if s.nil?

        log_output("Created server '#{s.name}' with id '#{s.id}'", :info)

        s.username = username
        s.private_key = private_key
        s.private_key_path = private_key_path
        servers << s
      end

      # save server ids for deprovisioning
      ids = servers.map {|s| s.id}
      set_field("#{provider}_ids", ids)
      set_field("cloud_ids", ids.concat(get_field("cloud_ids") || []))

      # if there was an error provisioning servers, return
      return if !get_field("__error__").nil? and !get_field("__error__").empty?

      # wait for servers to be up and set them up
      servers_ready = []
      servers_provisioned = []
      start = Time.now
      timeout = Fog.timeout
      while !servers.empty?
        server_names = servers.map{|s| s.name}.join(", ")
        duration = Time.now - start
        if duration > timeout
          log_output("Servers timed out before being ready: #{server_names}", :warn)
          break
        end

        log_output("Waiting for servers to be ready: #{server_names}")
        servers.each { |s| s.reload }
        s = servers.find { |s| s.ready? or s.error? }
        if s.nil?
          sleep(1)
        else
          if s.error?
            state = s.respond_to?('state') ? " with state: #{s.state}" : ""
            Maestro.log.warn "Server '#{s.name}' #{s.id} failed to start#{state}"
            write_output("failed#{state}\n")
            servers.delete(s)
          else
            log_output("Server '#{s.name}' #{s.id} is ready")
            servers_ready << servers.delete(s)
            # wait for servers to have public ip and run commands. Don't add provisioning time to timeout
            provision_start = Time.now
            servers_provisioned << on_ready(s, commands)
            start = start + (Time.now - provision_start)
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
      ids = get_field('instance_ids')  || []
      # otherwise use the ids of instances started previously
      if ids.empty?
        ids = []
        servers = read_output_value(SERVERS_CONTEXT_OUTPUT_KEY)
        unless servers.nil?
          servers.each {|server| ids << server['id'] if server['provider'] == provider }
        end
      end

      if ids.empty?
        log_output("No servers found to be deprovisioned", :warn)
        return
      end

      begin
        connection = connect(true)
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
        msg = "Unable to connect to #{provider}: #{e}"
        Maestro.log.error msg
        set_error msg
        return
      end

      ids.each do |id|
        log_output("Deprovisioning VM with id/name '#{id}'", :info)
        begin
          s = connection.servers.get(id) || connection.servers.find{|server| server_name(server) == id }

          if s.nil?
            log_output("VM with id/name '#{id}' not found, ignoring", :warn)
          else
            s.destroy
          end
          delete_server_on_master(s)
        rescue Exception => e
          log("Error destroying instance with id/name '#{id}'", e)
        end
      end

      log_output("Maestro #{provider} deprovision complete!", :info)
    end

    # save the server data in the Maestro database
    def create_server_on_master(s)
      image_id = server_image_id(s)   #s.respond_to?('image_id') ? s.image_id : 'no_image'
      flavor_id = server_flavor_id(s) #s.respond_to?('flavor_id') ? s.flavor_id : nil
      create_record_with_fields("machine",
        ["name",         "type",   "instance_id", "public_ipv4",       "image_id", "flavor_id"],
        [server_name(s), provider, s.id,          s.public_ip_address, image_id  , flavor_id])
    end

    def delete_server_on_master(s)
      delete_record("machine", server_name(s))
      # on new versions of maestro (4.10+)
      #delete_record("machine", {"instance_id" => s.id, "type" => provider})
    end

    # Get server name, or its id if name not supported
    # Some servers will expose a name attribute, but will return id - its up to them whether they support a
    # human readable name
    def server_name(s)
      (s.respond_to?('name') && s.name) ? s.name : s.id
    end
    
    # Get the image used to create a server
    def server_image_id(s)
      s.respond_to?('image_id') ? s.image_id : 'no_image'
    end
    
    # Get the flavor used to create a server.  Some providers support multiple flavors of an image,
    # for example, image X may be base install, with a flavor 'with mysql' (just an example) that adds
    # mysql to the base install
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

      populate_meta(server, 'new')

      server
    end

    # Clones an existing server
    def do_clone_server(connection, options)
      server = connection.vm_clone(options)
      yield(server) if block_given?

      populate_meta(server, 'clone')

      server
    end

    def get_server_by_id(connection, id)
      connection.servers.get(id)
    end

    def populate_meta(server, operation)
      if operation
        save_output_value('method', operation)
      end

      # Cannot use 'read_output_value' without ensuring the value is already set, otherwise it will
      # return the value from the previous run, so we will have to hack it until the read_output_value
      # method can take a "ignore_previous" type flag
      my_context_outputs = get_field(CONTEXT_OUTPUTS_META) || {}
      servers = my_context_outputs[SERVERS_CONTEXT_OUTPUT_KEY] || []

      server_meta_data = { 'id' => server.id, 'name' => server_name(server), 'image' => server_image_id(server), 'flavor' => server_flavor_id(server) , 'provider' => provider }
      ipv4 = s.public_ip_address
      server_meta_data['ipv4'] = ipv4 if ipv4
      servers << server_meta_data
      save_output_value(SERVERS_CONTEXT_OUTPUT_KEY, servers)

    end
  end
end

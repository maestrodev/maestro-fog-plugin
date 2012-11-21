require 'maestro_agent'
require 'fog'

module MaestroDev
  class FogWorker < Maestro::MaestroWorker

    def log(message, exception)
      msg = "#{message}: #{exception.message}\n#{exception.backtrace.join("\n")}"
      Maestro.log.error msg
      set_error(msg)
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

    def connect
      opts = get_field("#{provider}_connect_options")
      if opts.nil?
        opts = connect_options
        opts.each { |k,v| set_field(k.to_s, v) }
      end
      Fog::Compute.new(opts.merge(:provider => provider))
    end

    # character to use to split names with random_name
    def name_split_char
      "-"
    end

    # create 5 random chars if name not provided
    # if it's a fully qualified domain add them to the host name only
    def random_name(basename = "maestro")
      parts = basename.split(".")
      parts[0]="#{parts[0]}#{name_split_char}#{(0...5).map{ ('a'..'z').to_a[rand(26)] }.join}"
      parts.join(".")
    end

    # returns an array with errors, or empty if successful
    def provision_execute(s, commands)
      host = s.public_ip_address

      errors = []
      return errors if (commands == nil) || (commands == '') || Fog.mocking?

      msg = "Running SSH Commands On New Machine #{host} - #{commands.join(", ")}"
      Maestro.log.info msg
      write_output "#{msg}\n"

      for i in 1..10
        begin
          responses = s.ssh(commands)
          responses.each do |result|
            e = result.stderr
            o = result.stdout

            msg = "[#{host}] Ran Command #{result.command} With Output:\n#{o}\n"
            Maestro.log.debug msg
            write_output msg

            if !result.stderr.nil? && result.stderr != ''
              msg = "[#{host}] Stderr:\n#{o}"
              Maestro.log.debug msg
              write_output "#{msg}\n"
            end

            if result.status != 0
              msg = "[#{host}] Command '#{result.command}' failed with status #{result.status}"
              errors << msg
              Maestro.log.info msg
              write_output "#{msg}\n"
            end

          end unless responses.nil?
          break
        rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::SSH::Disconnect => e
          msg = "[#{host}] Try #{i} - failed to connect: #{e}, retrying..."
          write_output "#{msg}\n"
          Maestro.log.warn msg
          i = i+1
          if i > 10
            msg = "[#{host}] Could not connect to remote machine after 10 attempts"
            errors << msg
            write_output "#{msg}\n"
            Maestro.log.warn msg
          else
            sleep 5
            next
          end
        end
      end
      return errors
    end

    def provision
      msg = "Starting #{provider} provision"
      Maestro.log.info msg
      write_output("#{msg}\n")

      errors = validate_provision_fields
      unless errors.empty?
        msg = "Not a valid fieldset, #{errors.join("\n")}"
        Maestro.log.error msg
        set_error msg
        return
      end

      begin
        connection = connect
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
        msg = "Unable to connect to #{provider}: #{e}"
        Maestro.log.error msg
        set_error msg
        return
      end

      servers = []

      number_of_vms = get_field('number_of_vms') || 1

      # validate ssh options
      commands = get_field('ssh_commands')
      username = get_field('ssh_user') || "root"
      private_key = get_field("private_key")
      private_key_path = get_field("private_key_path")
      if !(commands.nil? or commands.empty?)
        if private_key.nil? and private_key_path.nil?
          msg = "private_key or private_key_path is required for SSH"
          Maestro.log.error msg
          set_error msg
          return
        end
      end

      has_private_ips = false

      name = get_field('name')
      existing_names = connection.servers.map {|s| s.name} if !name.nil? and number_of_vms==1
      # guarantee unique name if name is specified but taken already or launching more than 1 vm
      randomize_name = (!name.nil? and (number_of_vms > 1 or existing_names.include?(name)))

      # start the servers
      (1..number_of_vms).each do |i|

        # create the server in the cloud provider
        s = create_server(connection, randomize_name ? random_name(name) : name)

        if s.nil? && get_field("__error__").nil?
          msg = "Failed to create VM"
          Maestro.log.error msg
          set_error msg
        end
        break if s.nil?

        msg = "Started VM '#{s.name}' with id '#{s.id}'"
        Maestro.log.info msg
        write_output("#{msg}\n")

        servers << s
      end

      # save server ids for deprovisioning
      ids = servers.map {|s| s.id}
      set_field("#{provider}_ids", ids)
      set_field("cloud_ids", ids.concat(get_field("cloud_ids") || []))

      # if there was an error provisioning one of the servers, return
      return if !get_field("__error__").nil?

      # wait for servers to be up and set them up
      servers.each do |s|
        s.wait_for { ready? and !public_ip_address.nil? and !public_ip_address.empty? }

        unless s.ready? and !s.public_ip_address.nil? and !s.public_ip_address.empty?
          msg1 = s.ready? ? "get a public ip" : "be ready"
          msg = "Timed out waiting for server #{s.id} '#{s.name}' to #{msg1}"
          Maestro.log.error msg
          set_error msg
          break
        end

        if s.respond_to?('addresses') && !s.addresses.nil? && !s.addresses["private"].nil?
          private_addr = s.addresses["private"][0]["addr"]
          has_private_ips = true
        else
          private_addr = ''
        end

        msg = "Started VM '#{s.name}' with public ip '#{s.public_ip_address}' and private ip '#{private_addr}'"
        Maestro.log.info msg
        write_output("#{msg}\n")

        s.username = username
        s.private_key = private_key
        s.private_key_path = private_key_path

        setup_server(s)
      end

      # if there was an error provisioning one of the servers, return
      return if !get_field("__error__").nil?

      # save some values in the workitem so they are accessible for deprovision and other tasks
      # addresses={"private"=>[{"version"=>4, "addr"=>"10.20.0.37"}]},
      if (has_private_ips)
        private_ips = servers.map { |s| s.addresses["private"][0]["addr"] }
        set_field("#{provider}_private_ips", private_ips)
        set_field("cloud_private_ips", private_ips.concat(get_field("cloud_private_ips") || []))
      end
      ips = servers.map {|s| s.public_ip_address}
      set_field("#{provider}_ips", ips)
      set_field("cloud_ips", ips.concat(get_field("cloud_ips") || []))

      # run provisioning commands through ssh
      errors = []
      servers.each do |s|
        errors << provision_execute(s, commands)
      end
      errors.flatten!
      set_error(errors.join("\n")) unless errors.empty?

      msg = "Maestro #{provider} provision complete!"
      Maestro.log.debug msg
      write_output("#{msg}\n")
    end

    def deprovision
      msg = "Starting #{provider} deprovision"
      Maestro.log.info msg
      write_output("#{msg}\n")

      ids = get_field("#{provider}_ids")

      if ids.nil?
        msg = "No servers found to be deprovisioned"
        Maestro.log.warn msg
        write_output("#{msg}\n")
        return
      end

      begin
        connection = connect
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
        msg = "Unable to connect to #{provider}: #{e}"
        Maestro.log.error msg
        set_error msg
        return
      end

      ids.each do |id|
        msg = "Deprovisioning VM with id '#{id}'"
        Maestro.log.info msg
        write_output("#{msg}\n")
        begin
          s = connection.servers.get(id)

          if s.nil?
            msg = "VM with id '#{id}' not found, ignoring"
            Maestro.log.warn msg
            write_output("#{msg}\n")
          else
            s.destroy
          end
        rescue Exception => e
          log("Error destroying instance with id '#{id}'", e)
        end
      end

      msg = "Maestro #{provider} deprovision complete!"
      Maestro.log.debug msg
      write_output("#{msg}\n")
    end

  end

end

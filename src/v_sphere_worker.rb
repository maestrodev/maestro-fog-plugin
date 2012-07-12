require 'maestro_agent'
require 'fog'
require 'fog/compute/models/server'

module Fog
  module Compute
    class Vsphere

      # Add missing fields necessary for ssh
      # Taken from AWS Server
      class Server < Fog::Compute::Server
        attribute :public_ip_address,     :aliases => 'ipAddress'
        attr_writer   :private_key, :private_key_path, :username

        def username
          @username ||= 'root'
        end

        def private_key_path
          @private_key_path ||= Fog.credentials[:private_key_path]
          @private_key_path &&= File.expand_path(@private_key_path)
        end

        def private_key
          @private_key ||= private_key_path && File.read(private_key_path)
        end
      end
    end
  end
end


module MaestroDev
  class VSphereWorker < Maestro::MaestroWorker

    def log(message, exception)
      msg = "#{message}: #{exception.message}\n#{exception.backtrace.join("\n")}"
      Maestro.log.error msg
      set_error(msg)
    end

    def required_fields
      ['host', 'datacenter', 'username', 'password', 'template_name', 'vm_name']
    end

    def validate_provision_fields
      errors = []
      required_fields.each{|s|
        errors << "missing #{s}" if get_field(s).nil? || get_field(s).empty?
      }
      return errors
    end

    def connect(username, password, host)
      Fog::Compute.new(
        :provider => "vsphere",
        :vsphere_username => username,
        :vsphere_password => password,
        :vsphere_server => host)
    end

    # returns an array with errors, or empty if successful
    def provision_execute(s)
      commands = get_field('ssh_commands')
      s.username = get_field('ssh_user') || "root"
      s.private_key_path = get_field("private_key_path")
      host = (s.hostname.nil? || (s.hostname == '')) ? s.public_ip_address : s.hostname

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
    end

    def provision
      msg = "Starting vSphere provision"
      Maestro.log.info msg
      write_output("#{msg}\n")

      errors = validate_provision_fields
      unless errors.empty?
        msg = "Not a valid fieldset, #{errors.join("\n")}"
        Maestro.log.error msg
        set_error msg
        return
      end

      host = get_field('host')
      datacenter = get_field('datacenter')
      username = get_field('username')
      password = get_field('password')
      template_name = get_field('template_name')
      vm_name = get_field('vm_name')
      count = get_field('count') || 1

      begin
        connection = connect(username, password, host)
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
        msg = "Unable to connect to vSphere at '#{host}': #{e}"
        Maestro.log.error msg
        set_error msg
        return
      end

      ips = []
      hostnames = []
      ids = []
      servers = []

      (1..count).each do |i|
        name = count > 1 ? "#{vm_name}#{i}" : vm_name
        msg = "Cloning VM #{template_name} into #{name}"
        Maestro.log.info msg
        write_output("#{msg}\n")

        path = "/Datacenters/#{datacenter}/#{template_name}"
        begin
          # easier to do vm_clone than find the server and then clone
          cloned = connection.vm_clone(
            'name' => name,
            'path' => path,
            'poweron' => true,
            'wait' => true)
        rescue Fog::Compute::Vsphere::NotFound => e
          msg = "VM template '#{path}' not found" 
          Maestro.log.error msg
          set_error msg
          return
        rescue Exception => e
          log("Error cloning template '#{path}' as '#{name}'", e) and return
        end
        s = connection.servers.get(cloned['vm_ref'])

        if s.nil?
          msg = "Failed to clone VM '#{path}' as '#{name}'" 
          Maestro.log.error msg
          set_error msg
          return
        end

        msg = "Started VM '#{s.name}' with hostname '#{s.hostname}' and ip '#{s.ipaddress}'"
        Maestro.log.info msg
        write_output("#{msg}\n")

        s.public_ip_address = s.ipaddress # needed for ssh

        servers << s
        ips << s.ipaddress
        hostnames << s.hostname
        ids << s.id
      end

      # run provisioning commands through ssh
      errors = []
      servers.each do |s|
        errors += provision_execute(s)
      end
      set_error(errors.join("\n")) unless errors.empty?

      # save some values in the workitem so they are accessible for deprovision and other tasks
      set_field('vsphere_host', host)
      set_field('vsphere_username', username)
      set_field('vsphere_password', password)
      set_field('vsphere_ips', ips)
      set_field('vsphere_hostnames', hostnames)
      set_field('vsphere_ids', ids)

      msg = "Maestro::VSphereWorker::provision complete!"
      Maestro.log.debug msg
      write_output("#{msg}\n")
    end
    
    def deprovision
      msg = "Starting vSphere deprovision"
      Maestro.log.info msg
      write_output("#{msg}\n")

      host = get_field('vsphere_host')
      username = get_field('vsphere_username')
      password = get_field('vsphere_password')
      ids = get_field('vsphere_ids')

      begin
        connection = connect(username, password, host)
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
        msg = "Unable to connect to vSphere at '#{host}': #{e}"
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
            set_error msg
          else
            if s.ready? # turn off before destroying
              msg = "VM '#{id}' is running, stopping it"
              Maestro.log.info msg
              write_output("#{msg}\n")
              s.stop
            end
            s.destroy
          end
        rescue Exception => e
          log("Error destroying instance with id '#{id}'", e)
        end
      end

      msg = "Maestro::VSphereWorker::deprovision complete!"
      Maestro.log.debug msg
      write_output("#{msg}\n")
    end
    
  end

end

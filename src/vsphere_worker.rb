require 'pp'
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

    def validate_provision_fields
      errors = []
      ['host', 'datacenter', 'username', 'password', 'template_name', 'vm_name'].each{|s|
        errors << "missing #{s}" if workitem.fields[s].nil? || workitem.fields[s].empty?
      }
      raise "Not a valid fieldset, #{errors.join("\n")}" unless errors.empty?
    end

    def provision_execute(s)
      commands = workitem.fields['ssh_commands']
      s.username = workitem.fields['ssh_user'] || "root"
      s.private_key_path = workitem.fields["private_key_path"]

      return if (commands == nil) || (commands == '') || Fog.mocking?

      msg = "Running SSH Commands On New Machine #{s.hostname} - #{commands.join(", ")}"
      Maestro.log.info msg
      write_output "#{msg}\n"

      for i in 1..10
        begin
          responses = s.ssh(commands)
          responses.each do |result|
            e = result.stderr
            o = result.stdout

            if !result.stderr.nil? && result.stderr != '' 
              Maestro.log.info "[#{s.hostname}] #{result.command} -> #{e}"
              write_output "\nSSH command error: #{e}\n"
              raise SshError, "SSH command error: #{e}"
            end
            if result.stdout.include? 'command not found'
              raise Exception, "Remote command not found: #{result.command}"
            end
            Maestro.log.info "[#{s.hostname}] #{result.command} -> #{o}"

            write_output "\nConnected To #{s.hostname}, Ran Command #{result.command} With Output:\n#{o}"

          end unless responses.nil?
          break
        rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::SSH::Disconnect => e
          write_output "\n[#{s.hostname}] Try #{i} - failed to connect: #{e}, retrying..."
          Maestro.log.warn "[#{s.hostname}] Try #{i} - failed to connect: #{e}, retrying..."
          i = i+1
          if i > 10
            workitem.fields['__error__'] = "Could not connect to remote machine"
            raise SshError, "Could not connect to remote machine"
          else
            sleep 5
            next
          end
        end
      end
    end

    def provision
      begin
        msg = "Starting vSphere provision"
        Maestro.log.info msg
        write_output("#{msg}\n")

        validate_provision_fields

        host = get_field('host')
        datacenter = get_field('datacenter')
        username = get_field('username')
        password = get_field('password')
        template_name = get_field('template_name')
        vm_name = get_field('vm_name')
        count = get_field('count') || 1

        connection = Fog::Compute.new(
          :provider => "vsphere",
          :vsphere_username => username,
          :vsphere_password => password,
          :vsphere_server => host)        

        ips = []
        hostnames = []
        instance_uuids = []

        (1..count).each do |i|
          name = count > 1 ? "#{vm_name}#{i}" : vm_name
          msg = "Cloning VM #{template_name} into #{name}"
          Maestro.log.info msg
          write_output("#{msg}\n")

          # easier to do vm_clone than find the server and then clone
          cloned = connection.vm_clone(
            'name' => name,
            'path' => "/Datacenters/#{datacenter}/#{template_name}",
            'poweron' => true,
            'wait' => true)
          s = connection.servers.get(cloned['vm_ref'])

          raise "Failed to clone VM #{template_name} into #{name}" if s.nil?

          msg = "Started VM #{s.name} #{s.hostname} #{s.ipaddress}"
          Maestro.log.info msg
          write_output("#{msg}\n")

          s.public_ip_address = s.ipaddress # needed for ssh
          provision_execute(s)

          ips << s.ipaddress
          hostnames << s.hostname
          instance_uuids << s.instance_uuid
        end
        workitem.fields['ip'] = ips
        workitem.fields['hostname'] = hostnames

      rescue Exception => e
        msg = "Error Provisioning: #{e.message}\n#{e.backtrace.join("\n")}"
        Maestro.log.error msg
        set_error(msg)
        raise e
      end

      msg = "Maestro::VSphereWorker::provision complete!"
      Maestro.log.debug msg
      write_output("#{msg}\n")
    end
    
    def deprovision
      begin
        msg = "Starting vSphere deprovision"
        Maestro.log.info msg
        write_output("#{msg}\n")

        host = get_field('host')
        username = get_field('username')
        password = get_field('password')
        instance_uuids = get_field('instance_uuids')

        connection = Fog::Compute.new(
          :provider => "vsphere",
          :vsphere_username => username,
          :vsphere_password => password,
          :vsphere_server => host)        

        instance_uuids.each do |instance_uuid|
          msg = "Deprovisioning VM #{instance_uuid}"
          Maestro.log.info msg
          write_output("#{msg}\n")
          
          connection.vm_destroy('instance_uuid' => instance_uuid)
        end

      rescue Exception => e
        msg = "Error Deprovisioning: #{e.message}\n#{e.backtrace.join("\n")}"
        Maestro.log.error msg
        set_error(msg)
      end

      msg = "Maestro::VSphereWorker::deprovision complete!"
      Maestro.log.debug msg
      write_output("#{msg}\n")
    end
    
  end

end

require 'maestro_plugin'
require 'fog_worker'
require 'fog'
require 'fog/compute/models/server'

module Fog
  module Compute
    class Vsphere
      class Server < Fog::Compute::Server
        def state
          power_state
        end
        def image_id
          path
        end
      end
    end
  end
end

module MaestroDev
  module Plugin
    class VSphereWorker < FogWorker
  
      def provider
        "vsphere"
      end
  
      def required_fields
        ['host', 'username', 'password', 'template_path']
      end
  
      def connect_options
        {
          :vsphere_server   => get_field('host'),
          :vsphere_username => get_field('username'),
          :vsphere_password => get_field('password')
        }
      end
  
      def name_split_char
        "_"
      end
  
      def create_server(connection, name, options={})
        datacenter = get_field('datacenter')
        template_path = get_field('template_path')
        dest_folder = get_field('destination_folder')
        datastore = get_field('datastore')
        full_dest_path = (dest_folder.nil? or dest_folder.empty?) ? name : "#{dest_folder}/#{name}"
  
        msg = "Cloning VM in datacenter #{datacenter}: #{template_path} into #{full_dest_path}"
        Maestro.log.info msg
        write_output("#{msg}\n")
  
        options = {
          'datacenter' => datacenter,
          'name' => name,
          'template_path' => template_path,
          'poweron' => true,
          'wait' => false
        }
  
        if dest_folder && !dest_folder.empty?
          options['dest_folder'] = dest_folder
        end
        if datastore && !datastore.empty?
          options['datastore'] = datastore
        end
  
        begin
          # easier to do vm_clone than find the server and then clone
          cloned = do_clone_server(connection, options)
        rescue ArgumentError, Fog::Errors::NotFound => e
          msg = "VM template '#{template_path}': #{e}"
          Maestro.log.error msg
          set_error msg
          return
        rescue Exception => e
          log("Error cloning template '#{template_path}' as '#{full_dest_path}'", e)
          return
        end
  
        id = cloned["new_vm"] ? cloned["new_vm"]["id"] : nil
        if id.nil?
          msg = "VSphere failed to return cloned VM id while cloning '#{template_path}' as '#{full_dest_path}'"
          Maestro.log.error msg
          set_error msg
          return
        end
  
        s = get_server_by_id(connection, id)
        if s.nil?
          msg = "Failed to find newly cloned VM with id #{id} while cloning '#{template_path}' as '#{full_dest_path}'"
          Maestro.log.error msg
          set_error msg
          return
        end
        return s
      end
  
      private
  
      # Clones an existing server. Returns a Hash
      def do_clone_server(connection, options)
        server_data = connection.vm_clone(options)
        yield(server_data) if block_given?
        server_data
      end
  
    end
  
  end
end

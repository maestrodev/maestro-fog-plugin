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

      def associate_address
        validate_associate_address_fields
        connection = connect

        eip = connection.addresses.get(@ip_addr)
        raise PluginError, "Unable to locate elastic ip address #{@ip_addr}" unless eip

        if eip.server_id && eip.server_id.eql?(@instance_id)
          write_output("IP #{@ip_addr} not assigned to any instances, no need to update")
        else
          if eip.server_id && !eip.server_id.eql?(@instance_id)
            raise PluginError, "Elastic ip address #{@ip_addr} is already associated with server id #{eip.server_id} and 'reassign_if_assigned' was not set to true, not updating" unless @reassign_if_assigned

            # Need to disassociate before reassociating.  Fog doesn't support the one-stop version of this
            write_output("Elastic ip #{@ip_addr} is already associated with instance #{eip.server_id}, disassociating")

            # Yes, I did this.. I'm not proud, but the fog testing disassociate method exposes the wrong signature, and wouldn't work anyway.
            # Maybe when they support the 'association_id' param we can do away with this nastiness
            if Fog.mock?
              connection.disassociate_address(@ip_addr)
            else
              connection.disassociate_address(nil, eip['associationId'])
            end

            # Needed because of non-backwards \n on connect, and we don't want a bunch of blank lines.
            write_output("\n", :buffer => true)
          end

          write_output("Associating elastic ip #{@ip_addr} with instance #{@instance_id}")

          connection.associate_address(@instance_id,nil,nil,eip.allocation_id)
        end
      end

      def disassociate_address
        validate_disassociate_address_fields
        connection = connect

        eip = connection.describe_addresses('public-ip' => [@ip_addr])[:body]['addressesSet'][0]

        raise PluginError, "Unable to locate elastic ip address #{@ip_addr}" unless eip

        existing_id = eip['instanceId'] || ''

        unless existing_id.empty?

          # If an instance_id was supplied, we check to ensure the ip address is assigned to it before
          # we drop it.  If assigned to something else, bail
          unless @instance_id.empty?
            raise PluginError, "Elastic ip address #{@ip_addr} is not associated with instance #{@instance_id}.  Not updating.  (Associated with instance #{existing_id})" unless @instance_id.eql?(existing_id)
          end

          write_output("Disassociating elastic ip #{@ip_addr} from instance #{existing_id}")

          # Yes, I did this.. I'm not proud, but the fog testing disassociate method exposes the wrong signature, and wouldn't work anyway.
          # Maybe when they support the 'association_id' param we can do away with this nastiness
          if Fog.mock?
            connection.disassociate_address(@ip_addr)
          else
            connection.disassociate_address(nil, eip['associationId'])
          end
        else
          write_output("IP #{@ip_addr} not assigned to any instances, no need to update")
        end
      end

      def validate_connect_fields
        errors = []

        errors << 'aws access_key_id missing' if get_field('access_key_id', '').empty?
        errors << 'aws secret_access_key missing' if get_field('secret_access_key', '').empty?

        return errors
      end

      def validate_common_address_fields
        errors = validate_connect_fields

        @ip_addr = get_field('ip_address', '')

        if @ip_addr.empty?
          errors << 'ip_address not specified (you must specify the ip address to assign)'
        else
          errors << "ip_address '#{@ip_addr}' doesn't look like a valid ipv4 address" unless @ip_addr.match(/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/)
        end

        return errors
      end

      def validate_disassociate_address_fields
        errors = validate_common_address_fields

        # We don't need to validate this, since it is optional field
        @instance_id = get_field('instance_id', '')

        raise ConfigError, "Configuration Errors: #{errors.join(", ")}" unless errors.empty?
      end

      def validate_associate_address_fields
        errors = validate_common_address_fields

        @instance_id = get_field('instance_id', '')

        if @instance_id.empty?
          # if context 'cloud_ids.size' == 1, use that, otherwise bail
          cloud_ids = get_field('cloud_ids', [])

          if cloud_ids.size == 1
            @instance_id = cloud_ids[0]
          end
        end

        @reassign_if_assigned = get_boolean_field('reassign_if_assigned')

        errors << 'instance_id missing (you must specify the instance_id of the instance to assign the ip address to, or a previous task must have created ONE instance)' if @instance_id.empty?

        raise ConfigError, "Configuration Errors: #{errors.join(", ")}" unless errors.empty?
      end

    end
  end
end

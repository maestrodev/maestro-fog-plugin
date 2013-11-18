require 'maestro_plugin'
require 'fog'
require 'fog/core/model'

module Fog
  module DNS
    class AWS

      class Record < Fog::Model

        def initialize(attributes={})
          puts attributes
          super
        end

        def ready?
          # requires :change_id, :status
          status == 'INSYNC'
        end


        def save
          self.ttl ||= 3600
          options = attributes_to_options('CREATE')
          data = service.change_resource_record_sets(zone.id, [options]).body
          merge_attributes(data)
          true
        end

        def reload
          # If we have a change_id (newly created or modified), then reload performs a get_change to update status.
          if change_id
            data = service.get_change(change_id).body
            merge_attributes(data)
            self
          else
            super
          end
        end
      end
    end
  end
end


module MaestroDev
  module Plugin
    class DnsWorker < Maestro::MaestroWorker
    
      def get_timer_from_soa(soa)
        soa.split(/\s/)[2]
      end
    
      def increment_timer_from_soa(timer)
        date_match = timer.match(/\d{4}\d{2}\d{2}/)
        date = date_match.nil? ? nil : Date.strptime(date_match[0], "%Y%m%d")
  
        if date and date == Date.today
          #increment counter
          tick = timer.match(/\d{4}\d{2}\d{2}(\d{2})/)[1]
  
          tick = (tick.to_i + 1) <= 9 ? "0" + (tick.to_i + 1).to_s : (tick.to_i + 1).to_s
          return timer if tick.to_i >= 100
  
          date.strftime("%Y%m%d") + tick
        else
          #increment day reset counter
          Date.today.strftime("%Y%m%d") + "01"
        end
      end
    
      def replace_timer_in_soa(soa, timer)
        columns = soa.split(/\s/)
        columns[2] = timer
        columns.join(" ")
      end
    
      def update_soa_record(soa_record)
        write_output("Updating SOA record...")
        soa = soa_record.value.first
        timer = get_timer_from_soa(soa)
        timer = increment_timer_from_soa(timer)
        soa = replace_timer_in_soa(soa, timer)
        soa_record.modify(:value => [soa])
        write_output(" Updated\n")
        write_output("New Value :: #{soa_record.value.first}\n")
        soa_record
      end
    
      def connect_dns
        Fog::DNS.new({
          :provider               => 'AWS',
          :aws_access_key_id      => get_field('access_key_id'),
          :aws_secret_access_key  => get_field('secret_access_key')
        })
      end
    
      def find_zone(dns, zone_name)
        write_output("Searching For Zone #{zone_name}... ")
        zone = dns.zones.all.find{|z| z.domain == zone_name}
        if(zone)
          write_output("Found\n")
        else
          write_output("Failed\n")
          set_error("Failed To Find Zone #{zone_name}")
        end
        return zone
      end
    
      def create_record(dns, zone)
        data = {
          :value => get_field('dns_value'),
          :name => get_field('dns_name'),
          :type => get_field('dns_type')
        }

        msg = "Creating Record #{data}"
        write_output("#{msg}...")
        Maestro.log.info(msg)
        start = Time.now
        record = zone.records.create(data)
        if(record)
          write_output(" Created (#{Time.now - start}s)\n")
        else
          write_output(" Failed (#{Time.now - start}s)\n")
          set_error("Failed To Create Record #{data}")
        end

        msg = "Waiting for Record #{data} to be ready"
        write_output("#{msg}...")
        Maestro.log.debug(msg)
        start = Time.now
        begin
          record.wait_for { ready? }
          write_output(" done (#{Time.now - start}s)\n")
        rescue Fog::Errors::TimeoutError => e
          msg = "Record #{record.name} timed out waiting to be ready"
          Maestro.log.warn(msg)
          write_output("failed (#{Time.now - start}s)\n")
          set_error("Record #{record.name} failed to be ready in #{Fog.timeout} seconds")
          return nil
        end
        
        # soa_record = zone.records.get(get_field('dns_zone'), "SOA")
        # soa_record = update_soa_record(soa_record)
  
        return record
      end
      
      def modify_record(dns, zone)
        data = {:value => get_field('dns_value'), :type => get_field('dns_type')}

        msg = "Modifying Record #{get_field('dns_name')} to #{data}"
        write_output("#{msg}...")
        Maestro.log.info(msg)
        start = Time.now
        record = zone.records.get(get_field('dns_name'))
        if(record)
          record.modify(data)
          write_output(" Updated (#{Time.now - start}s)\n")
        else
          write_output(" Failed (#{Time.now - start}s)\n")
          set_error("Failed To Modify Record, Unable to find record #{get_field('dns_name')}")
        end

        msg = "Waiting for Record #{record.name} to be ready"
        write_output("#{msg}...")
        Maestro.log.debug(msg)
        start = Time.now
        begin
          record.wait_for { ready? }
          write_output(" done (#{Time.now - start}s)\n")
        rescue Fog::Errors::TimeoutError => e
          msg = "Record #{record.name} timed out waiting to be ready"
          Maestro.log.warn(msg)
          write_output("failed (#{Time.now - start}s)\n")
          set_error("Record #{record.name} failed to be ready in #{Fog.timeout} seconds")
          return nil
        end

        # soa_record = zone.records.get(get_field('dns_zone'), "SOA")
        # soa_record = update_soa_record(soa_record)
  
        return record
      end
      
      def create
        dns = connect_dns
        zone = find_zone(dns, get_field('dns_zone')) if !error?
        record = create_record(dns, zone) if !error?
      end
      
      def modify
        dns = connect_dns
        zone = find_zone(dns, get_field('dns_zone')) if !error?
        record = modify_record(dns, zone) if !error?
      end
      
    end
  end
end

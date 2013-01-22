require 'maestro_agent'
require 'fog'
require 'fog/core/model'

module MaestroDev
  class DnsWorker < Maestro::MaestroWorker
  
    def connect_dns
      dns = Fog::DNS.new({
        :provider               => 'AWS',
        :aws_access_key_id      => get_field('access_key_id'),
        :aws_secret_access_key  => get_field('secret_access_key')
      })
    end
  
    def find_zone(dns)
      write_output("Searching For Zone #{get_field('dns_zone')}... ")
      zone = dns.zones.create(
        :domain => get_field('dns_zone')
      )
      if(zone)
        write_output("Found")
      else
        write_output("Failed\n")
        set_error("Failed To Find Zone #{get_field('dns_zone')}")
      end
      return zone
    end
  
    def create_record(dns, zone)
      write_output("\nCreating Record Name = #{get_field('dns_name')}, Value = #{get_field('dns_value')}, Type = #{get_field('dns_type')}...")
        record = zone.records.create(
          :value   => get_field('dns_value'),
          :name => get_field('dns_name'),
          :type => get_field('dns_type')
        )          
      if(record)
        write_output(" Created\n")
      else
        write_output("Failed\n")
        set_error("Failed To Create Record")
      end
      return record
    end
    
    def work
      begin
        dns = connect_dns
        
        zone = find_zone(dns) if !error?
        record = create_record(dns, zone) if !error
      rescue StandardError => e
        set_error("Failed To Create Record Zone = #{get_field('dns_zone')} Name = #{get_field('dns_name')}, Value = #{get_field('dns_value')}, Type = #{get_field('dns_type')} " + e)
      end        
    end
    
  end
end
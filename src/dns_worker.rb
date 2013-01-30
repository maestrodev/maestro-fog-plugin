require 'maestro_agent'
require 'fog'
require 'fog/core/model'

module MaestroDev
  class DnsWorker < Maestro::MaestroWorker
  
    def get_timer_from_soa(soa)
      soa.split(/\s/)[2]
    end
  
    def increment_timer_from_soa(timer)
      date = timer.match(/\d{4}\d{2}\d{2}/).andand[0]
      date = Date.strptime(date, "%Y%m%d") unless date.nil?

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
      dns = Fog::DNS.new({
        :provider               => 'AWS',
        :aws_access_key_id      => get_field('access_key_id'),
        :aws_secret_access_key  => get_field('secret_access_key')
      })
    end
  
    def find_zone(dns)
      write_output("Searching For Zone #{get_field('dns_zone')}... ")
      zone = dns.zones.all.find{|zone| zone.domain == get_field('dns_zone')}
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
      
      # soa_record = zone.records.get(get_field('dns_zone'), "SOA")
      # soa_record = update_soa_record(soa_record)

      return record
    end
    
    def work
      begin
        dns = connect_dns
        
        zone = find_zone(dns) if !error?
        record = create_record(dns, zone) if !error?
      rescue StandardError => e
        set_error("Failed To Create Record Zone = #{get_field('dns_zone')} Name = #{get_field('dns_name')}, Value = #{get_field('dns_value')}, Type = #{get_field('dns_type')} " + e)
        puts e, e.backtrace.join("\n")
      end        
    end
    
  end
end
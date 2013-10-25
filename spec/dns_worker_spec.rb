require 'spec_helper'
require 'dns_worker'


describe MaestroDev::Plugin::DnsWorker do
  it "should create a new dns entry in route53" do
    subject.should_receive(:create_record)
    subject.should_receive(:connect_dns)
    subject.should_receive(:find_zone)
    
    fields = {
            "access_key_id" => "hello",
            "secret_access_key" => "hello",
            "dns_type" => "A",
            "dns_name" => "newhost",
            "dns_value" => "127.0.0.1",
            "dns_zone" => "maestrodev.net."
          }
    subject.stub(:workitem => {"fields" => fields})
    subject.create
  end
  
  it "should modify an exisiting dns entry in route53" do
    subject.should_receive(:modify_record)
    subject.should_receive(:connect_dns)
    subject.should_receive(:find_zone)
    
    fields = {
            "access_key_id" => "hello",
            "secret_access_key" => "hello",
            "dns_name" => "newhost",
            "dns_value" => "192.168.1.1",
            "dns_zone" => "maestrodev.net."
          }
    subject.stub(:workitem => {"fields" => fields})
    subject.modify
  end
  
  it "should parse the timer from a soa record and increment it" do
    soa = "ns-1613.awsdns-09.co.uk. awsdns-hostmaster.amazon.com. 2013011501 7200 900 86400 3600"

    timer = subject.get_timer_from_soa(soa)
    
    timer.should eql("2013011501")
    
    new_timer = subject.increment_timer_from_soa(timer)
    
    new_timer.should eql(Time.now.strftime("%Y%m%d")+ "01")
    
    new_timer = subject.increment_timer_from_soa(new_timer)
    new_timer.should eql(Time.now.strftime("%Y%m%d")+ "02")
    
    3.upto(9) do |number|
      new_timer = subject.increment_timer_from_soa(new_timer)
      new_timer.should eql(Time.now.strftime("%Y%m%d")+ "0#{number}")
    end
    
    10.upto(99) do |number|
      new_timer = subject.increment_timer_from_soa(new_timer)
      new_timer.should eql(Time.now.strftime("%Y%m%d")+ "#{number}")
    end
    
    old_timer = new_timer
    100.upto(101) do |number|
      new_timer = subject.increment_timer_from_soa(new_timer)
      new_timer.should eql(old_timer)
    end
    
    new_soa = subject.replace_timer_in_soa(soa, new_timer)
    new_soa.should eql("ns-1613.awsdns-09.co.uk. awsdns-hostmaster.amazon.com. #{new_timer} 7200 900 86400 3600")
  end
  
  
  it "should parse the timer from a soa record and increment it if it is only an increment" do
    soa = "ns-1613.awsdns-09.co.uk. awsdns-hostmaster.amazon.com. 1 7200 900 86400 3600"

    timer = subject.get_timer_from_soa(soa)
    
    timer.should eql("1")
    
    new_timer = subject.increment_timer_from_soa(timer)
    
    new_timer.should eql(Time.now.strftime("%Y%m%d")+ "01")
    
    new_timer = subject.increment_timer_from_soa(new_timer)
    new_timer.should eql(Time.now.strftime("%Y%m%d")+ "02")
    
    3.upto(9) do |number|
      new_timer = subject.increment_timer_from_soa(new_timer)
      new_timer.should eql(Time.now.strftime("%Y%m%d")+ "0#{number}")
    end
    
    10.upto(99) do |number|
      new_timer = subject.increment_timer_from_soa(new_timer)
      new_timer.should eql(Time.now.strftime("%Y%m%d")+ "#{number}")
    end
    
    old_timer = new_timer
    100.upto(101) do |number|
      new_timer = subject.increment_timer_from_soa(new_timer)
      new_timer.should eql(old_timer)
    end
    
    new_soa = subject.replace_timer_in_soa(soa, new_timer)
    new_soa.should eql("ns-1613.awsdns-09.co.uk. awsdns-hostmaster.amazon.com. #{new_timer} 7200 900 86400 3600")
  end
end

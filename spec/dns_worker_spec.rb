require 'spec_helper'
require 'dns_worker'

describe MaestroDev::Plugin::DnsWorker do

  let(:record) {{ :name => "newhost2.maestrodev.net.", :type => "A", :value => ["127.0.0.1"], :ttl => "3600" }}
  let(:fields) {{
    "access_key_id" => "hello",
    "secret_access_key" => "hello",
    "dns_name" => record[:name],
    "dns_value" => record[:value],
    "dns_zone" => zone,
    "dns_type" => record[:type]
  }}
  let(:zone) { "maestrodev.net." }
  let(:connection) do
    Fog::DNS.new({
      :provider               => 'AWS',
      :aws_access_key_id      => 'hello',
      :aws_secret_access_key  => 'hello'})
  end

  before do
    connection.reset_data
    subject.stub(:workitem => {"fields" => fields}, :connect_dns => connection)
    connection.zones.create(:domain => zone)
  end

  context "when creating a new entry" do
    before do
      expect_any_instance_of(Fog::DNS::AWS::Record).to receive(:reload).at_least(2).times.and_call_original
      @record = subject.create
    end
    its(:output) { should match(/Created \(.*s\)$/) }
    its(:output) { should_not match(/Failed|failed/) }
    its(:error) { should be_nil }
    it { connection.zones.size.should == 1 }
    it { connection.zones.first.records.size.should == 1 }
    it { connection.zones.first.records.first.attributes.should eq(record) }
    it { @record.ready?.should be_true }
  end
  
  context "when modifying an existing entry" do
    let(:record) { super().merge({:value => ["192.168.1.1"]}) }
    before do
      connection.zones.first.records.new(record.merge(:value => "127.0.0.1")).save
      expect_any_instance_of(Fog::DNS::AWS::Record).to receive(:reload).at_least(2).times.and_call_original
      @record = subject.modify
    end
    its(:output) { should match(/Updated \(.*s\)$/) }
    its(:output) { should_not match(/Failed|failed/) }
    its(:error) { should be_nil }
    it { connection.zones.size.should == 1 }
    it { connection.zones.first.records.size.should == 1 }
    it { connection.zones.first.records.first.attributes.should eq(record) }
    it { @record.ready?.should be_true }
  end

  describe :timer do
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
end

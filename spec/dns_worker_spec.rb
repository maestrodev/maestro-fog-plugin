require 'spec_helper'
require 'dns_worker'


describe MaestroDev::DnsWorker do
  it "should create a new dns entry in route53" do
    worker = MaestroDev::DnsWorker.new
    worker.should_receive(:create_record)
    worker.should_receive(:connect_dns)
    worker.should_receive(:find_zone)
    
    fields = {
            "access_key_id" => "hello",
            "secret_access_key" => "hello",
            "dns_type" => "A",
            "dns_name" => "newhost",
            "dns_value" => "127.0.0.1",
            "dns_zone" => "maestrodev.net."
          }
    wi = Ruote::Workitem.new({"fields" => fields})
    worker.stub(:workitem => wi.to_h)
    worker.work
  end
end
# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'fog_worker'
require 'fog/compute/models/server'

describe MaestroDev::FogWorker, :provider => "test" do

  class TestWorker < MaestroDev::FogWorker
    def provider
      "test"
    end
  end

  before(:all) do
    Fog.mock!
    @worker = TestWorker.new

    @ssh_user = "johndoe"
    @private_key = "aaaa"
  end

  def mock_server(id = 1, name = "test")
    server = Fog::Compute::Server.new(:id => id)
    server.stub(:name => name, :wait_for => true, :public_ip_address => '192.168.1.1')
    server.should_receive(:username=).with(@ssh_user)
    server.should_receive(:private_key_path=).with(nil)
    server.should_receive(:private_key=).with(@private_key)
    server
  end

  describe 'provision' do

    before(:each) do
      @fields = {
        "name" => "test",
        "params" => {"command" => "provision"},
        "ssh_user" => @ssh_user,
        "ssh_commands" => ["hostname"],
        "private_key" => @private_key
      }
    end

    it 'should provision a server' do
      wi = Ruote::Workitem.new({"fields" => @fields})
      @worker.stub(:workitem => wi.to_h)

      connection = double("connection", :servers => [])
      @worker.stub(:connect => connection)

      @worker.stub(:create_server => mock_server)
      @worker.provision

      wi.fields['__error__'].should be_nil
      wi.fields['cloud_ids'].should_not be_empty
      wi.fields['test_ids'].should_not be_empty
    end

    it 'should provision more than one server when name is not provided' do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"name" => nil, "number_of_vms" => 3})})
      @worker.stub(:workitem => wi.to_h)

      connection = double("connection", :servers => [])
      @worker.stub(:connect => connection)
      @worker.should_receive(:create_server).with(anything(), nil).and_return(
        mock_server(1), mock_server(2), mock_server(3))
      @worker.provision

      wi.fields['__error__'].should be_nil
      wi.fields['cloud_ids'].size.should == 3
      wi.fields['test_ids'].size.should == 3
    end

    it 'should provision more than one server with random names when name is provided' do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"number_of_vms" => 3})})
      @worker.stub(:workitem => wi.to_h)

      connection = double("connection", :servers => [])
      @worker.stub(:connect => connection)
      @worker.should_receive(:create_server).with(anything(), /^test-[a-z]{5}$/).and_return(
        mock_server(1), mock_server(2), mock_server(3))
      @worker.provision

      wi.fields['__error__'].should be_nil
      wi.fields['cloud_ids'].size.should == 3
      wi.fields['test_ids'].size.should == 3
    end

    it 'should fail if ssh is not properly configured' do
      wi = Ruote::Workitem.new({"fields" => @fields.reject {|k,v| k=="private_key"}})
      @worker.stub(:workitem => wi.to_h)
      @worker.stub(:connect => double("connection"))
      @worker.provision

      wi.fields['__error__'].should eq("private_key or private_key_path is required for SSH")
      wi.fields['cloud_ids'].should be_nil
      wi.fields['test_ids'].should be_nil
    end

    it 'should generate a random name' do
      @worker.random_name.should match(/^maestro-[a-z]{5}$/)
      @worker.random_name("test").should match(/^test-[a-z]{5}$/)
      s = "test.acme.com"
      @worker.random_name(s).should match(/^test-[a-z]{5}\.acme\.com$/)
      @worker.random_name(s).should match(/^test-[a-z]{5}\.acme\.com$/)
    end
  end

  describe 'deprovision' do

    before(:each) do
      @fields = {
        "params" => {"command" => "deprovision"},
        "rackspace_username" => @username,
        "rackspace_api_key" => @api_key
      }
    end

    it 'should destroy started servers' do
      server1 = Fog::Compute::Server.new(:id => 1)
      server2 = Fog::Compute::Server.new(:id => 2)
      stubs = [server1, server2]
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"test_ids" => stubs.map { |s| s.id }})})
      @worker.stub(:workitem => wi.to_h)
      servers = double("servers")
      @worker.stub(:connect => double("connection", :servers => servers))

      stubs.each do |s|
        servers.should_receive(:get).once.with(s.id).and_return(s)
        s.should_receive(:destroy).once
        s.should_not_receive(:stop)
      end

      @worker.deprovision
      wi.fields['__error__'].should be_nil
    end

    it 'should not fail if no servers were started' do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"rackspace_ids" => []})})
      @worker.stub(:workitem => wi.to_h)

      @worker.deprovision
      wi.fields['__error__'].should be_nil
    end

  end
end

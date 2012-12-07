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
    @worker = TestWorker.new

    @ssh_user = "johndoe"
    @private_key = "aaaa"
  end

  def mock_server_basic(id, name)
    server = Fog::Compute::Server.new(:id => id)
    server.class.identity("id")
    server.stub({:name => name, "ready?" => true, :reload => true})
    server
  end

  def mock_server(id=1, name="test")
    server = mock_server_basic(id, name)
    server.stub({:public_ip_address => '192.168.1.1'})
    server.should_receive(:username=).with(@ssh_user)
    server.should_receive(:private_key_path=).with(nil)
    server.should_receive(:private_key=).with(@private_key)
    server.should_receive(:ssh).once.and_return([ssh_result])
    server
  end
  def ssh_result
    r = Fog::SSH::Result.new("ssh command")
    r.status = 0
    r
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
      @worker.should_receive(:create_server).with(connection, "test").and_return(mock_server)
      @worker.provision

      wi.fields['__error__'].should be_nil
      wi.fields['cloud_ids'].compact.size.should == 1
      wi.fields['test_ids'].compact.size.should == 1
      wi.fields['cloud_ips'].compact.size.should == 1
      wi.fields['test_ips'].compact.size.should == 1
    end

    # in Rackspace v2 cloud servers may be ready but not have a public ip yet
    it 'should wait for public ip' do
      wi = Ruote::Workitem.new({"fields" => @fields})
      @worker.stub(:workitem => wi.to_h)

      connection = double("connection", :servers => [])
      @worker.stub(:connect => connection)
      server = mock_server_basic(1, "test")
      server.stub("ready?").and_return(true)
      ip = '192.168.1.1'
      server.should_receive(:ssh).once.and_return([ssh_result])
      server.stub(:public_ip_address).and_return(nil, nil, ip)
      @worker.stub(:create_server => server)
      @worker.provision

      wi.fields['__error__'].should be_nil
      wi.fields['cloud_ids'].compact.size.should == 1
      wi.fields['test_ids'].compact.size.should == 1
      wi.fields['cloud_ips'].compact.size.should == 1
      wi.fields['cloud_ips'].first.should eq(ip)
      wi.fields['test_ips'].compact.size.should == 1
    end

    it 'should fail if server does not have public ip' do
      wi = Ruote::Workitem.new({"fields" => @fields})
      @worker.stub(:workitem => wi.to_h)

      connection = double("connection", :servers => [])
      @worker.stub(:connect => connection)
      server = mock_server_basic(1, "test")
      server.stub("ready?").and_return(true)
      server.stub(:public_ip_address).and_return(nil)
      @worker.stub(:create_server => server)
      @worker.provision

      wi.fields['__error__'].should eq("All servers failed to get public ips")
      wi.fields['cloud_ids'].compact.size.should == 1
      wi.fields['test_ids'].compact.size.should == 1
      wi.fields['cloud_ips'].should be_nil
      wi.fields['test_ips'].should be_nil
    end

    it 'should not fail if some servers fail to start' do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"number_of_vms" => 2})})
      @worker.stub(:workitem => wi.to_h)

      connection = double("connection", :servers => [])
      @worker.stub(:connect => connection)
      server1 = mock_server_basic(1, "test 1")
      server1.stub("ready?").and_return(true)
      server1.stub(:public_ip_address).and_return(nil)
      server2 = mock_server(2, "test 2")
      @worker.should_receive(:create_server).and_return(server1, server2)
      @worker.provision

      wi.fields['__error__'].should be_nil
      wi.fields['cloud_ids'].compact.size.should == 2
      wi.fields['test_ids'].compact.size.should == 2
      wi.fields['cloud_ips'].compact.size.should == 1
      wi.fields['test_ips'].compact.size.should == 1
    end

    it 'should not fail if some servers fail to provision' do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"number_of_vms" => 2})})
      @worker.stub(:workitem => wi.to_h)

      connection = double("connection", :servers => [])
      @worker.stub(:connect => connection)
      server1 = mock_server(1, "test 1")
      server2 = mock_server_basic(2, "test 2")
      server2.stub(:public_ip_address => '1912.168.1.1')
      failed_ssh = ssh_result
      failed_ssh.status=1
      server2.should_receive(:ssh).once.and_return([failed_ssh])
      @worker.should_receive(:create_server).and_return(server1, server2)
      @worker.provision

      wi.fields['__error__'].should be_nil
      wi.fields['cloud_ids'].compact.size.should == 2
      wi.fields['test_ids'].compact.size.should == 2
      wi.fields['cloud_ips'].compact.size.should == 2
      wi.fields['test_ips'].compact.size.should == 2
    end

    it 'should fail if all servers fail to provision' do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"number_of_vms" => 2})})
      @worker.stub(:workitem => wi.to_h)

      connection = double("connection", :servers => [])
      @worker.stub(:connect => connection)
      server1 = mock_server_basic(1, "test 1")
      server2 = mock_server_basic(2, "test 2")
      server1.stub(:public_ip_address => '1912.168.1.1')
      server2.stub(:public_ip_address => '1912.168.1.2')
      failed_ssh = ssh_result
      failed_ssh.status=1
      server1.should_receive(:ssh).once.and_return([failed_ssh])
      server2.should_receive(:ssh).once.and_return([failed_ssh])
      @worker.should_receive(:create_server).and_return(server1, server2)
      @worker.provision

      wi.fields['__error__'].should eq("All servers failed to provision")
      wi.fields['cloud_ids'].compact.size.should == 2
      wi.fields['test_ids'].compact.size.should == 2
      wi.fields['cloud_ips'].compact.size.should == 2
      wi.fields['test_ips'].compact.size.should == 2
    end

    it 'should provision more than one server when name is not provided' do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"name" => nil, "number_of_vms" => 3})})
      @worker.stub(:workitem => wi.to_h)

      connection = double("connection", :servers => [])
      @worker.stub(:connect => connection)
      @worker.should_receive(:create_server).with(connection, nil).and_return(
        mock_server(1), mock_server(2), mock_server(3))
      @worker.provision

      wi.fields['__error__'].should be_nil
      wi.fields['cloud_ids'].compact.size.should == 3
      wi.fields['test_ids'].compact.size.should == 3
    end

    it 'should provision more than one server with random names when name is provided' do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"number_of_vms" => 3})})
      @worker.stub(:workitem => wi.to_h)

      connection = double("connection", :servers => [])
      @worker.stub(:connect => connection)
      @worker.should_receive(:create_server).with(connection, /^test-[a-z]{5}$/).and_return(
        mock_server(1), mock_server(2), mock_server(3))
      @worker.provision

      wi.fields['__error__'].should be_nil
      wi.fields['cloud_ids'].compact.size.should == 3
      wi.fields['test_ids'].compact.size.should == 3
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

    it 'should fail early if ssh key file does not exist' do
      wi = Ruote::Workitem.new({"fields" => @fields.reject {|k,v| k=="private_key"}.merge({"private_key_path" => "/blabla"})})
      @worker.stub(:workitem => wi.to_h)
      @worker.stub(:connect => double("connection"))
      @worker.provision

      wi.fields['__error__'].should eq("private_key_path does not exist: /blabla")
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

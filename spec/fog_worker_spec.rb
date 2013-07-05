# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'fog_worker'
require 'fog/compute/models/server'

describe MaestroDev::FogWorker, :provider => "test" do

  class TestWorker < MaestroDev::FogWorker
    def provider
      "test"
    end
    def connect_options
      {
        :test_hostname => get_field('hostname'),
        :test_username => get_field('username'),
        :test_password => get_field('password')
      }
    end
    def send_workitem_message
    end
  end

  subject { TestWorker.new }

  before(:each) do
    @hostname = "myhostname"
    @username = "myusername"
    @password = "mypassword"
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
    server.stub({:public_ip_address => "192.168.1.#{id}"})
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

    let(:fields) {{
        "name" => "test",
        "hostname" => @hostname,
        "username" => @username,
        "password" => @password,
        "params" => {"command" => "provision"},
        "ssh_user" => @ssh_user,
        "ssh_commands" => ["hostname"],
        "private_key" => @private_key
    }}

    it 'should provision a server' do
      subject.stub(:workitem => {"fields" => fields})

      connection = double("connection", :servers => [])
      Fog::Compute.stub(:new => connection)
      subject.should_receive(:create_server).with(connection, "test").and_return(mock_server)
      subject.provision

      subject.error.should be_nil
      subject.get_field('cloud_ids').should eq([1])
      subject.get_field('test_ids').should eq([1])
      subject.get_field('cloud_ips').should eq(["192.168.1.1"])
      subject.get_field('test_ips').should eq(["192.168.1.1"])
      subject.get_field('cloud_names').should eq(["test"])
      subject.get_field('test_names').should eq(["test"])
      subject.get_field('test_hostname').should eq("myhostname")
      subject.get_field('test_username').should eq("myusername")
      subject.get_field('test_password').should eq("mypassword")
    end

    it 'should provision several servers' do
      subject.stub(:workitem => {"fields" => fields.merge({"number_of_vms" => 3})})

      connection = double("connection", :servers => [])
      Fog::Compute.stub(:new => connection)
      server1 = mock_server(1, "test 1")
      server2 = mock_server(2, "test 2")
      server3 = mock_server(3, "test 3")
      subject.should_receive(:create_server).with(connection, /^test-[a-z]{5}$/).and_return(server1, server2, server3)
      subject.provision

      subject.error.should be_nil
      subject.get_field('cloud_ids').should eq([1, 2, 3])
      subject.get_field('test_ids').should eq([1, 2, 3])
      subject.get_field('cloud_ips').should eq(["192.168.1.1", "192.168.1.2", "192.168.1.3"])
      subject.get_field('test_ips').should eq(["192.168.1.1", "192.168.1.2", "192.168.1.3"])
      subject.get_field('cloud_names').should eq(["test 1", "test 2", "test 3"])
      subject.get_field('test_names').should eq(["test 1", "test 2", "test 3"])
      subject.get_field('test_hostname').should eq("myhostname")
      subject.get_field('test_username').should eq("myusername")
      subject.get_field('test_password').should eq("mypassword")
    end

    # in Rackspace v2 cloud servers may be ready but not have a public ip yet
    it 'should wait for public ip' do
      subject.stub(:workitem => {"fields" => fields})

      connection = double("connection", :servers => [])
      Fog::Compute.stub(:new => connection)
      server = mock_server_basic(1, "test")
      server.stub("ready?").and_return(true)
      ip = '192.168.1.1'
      server.should_receive(:ssh).once.and_return([ssh_result])
      server.stub(:public_ip_address).and_return(nil, nil, ip)
      subject.stub(:create_server => server)
      subject.provision

      subject.error.should be_nil
      subject.get_field('cloud_ids').should eq([1])
      subject.get_field('test_ids').should eq([1])
      subject.get_field('cloud_ips').should eq(["192.168.1.1"])
      subject.get_field('test_ips').should eq(["192.168.1.1"])
    end

    # in mCloud, servers don't have a public ip assigned automatically.
    it 'should not wait for public ip if not told to' do
      fields['wait_for_public_ip'] = false
      fields.delete('ssh_commands')
      subject.stub(:workitem => {"fields" => fields})

      connection = double("connection", :servers => [])
      Fog::Compute.stub(:new => connection)
      server = mock_server_basic(1, "test")
      server.stub("ready?").and_return(true)
      server.stub(:public_ip_address).and_return(nil)
      subject.stub(:create_server => server)
      subject.provision

      subject.error.should be_nil
      subject.get_field('cloud_ids').should eq([1])
      subject.get_field('test_ids').should eq([1])
      subject.get_field('cloud_ips').should be_nil
    end

    it 'should fail if server does not have public ip' do
      subject.stub(:workitem => {"fields" => fields})

      connection = double("connection", :servers => [])
      Fog::Compute.stub(:new => connection)
      server = mock_server_basic(1, "test")
      server.stub("ready?").and_return(true)
      server.stub(:public_ip_address).and_return(nil)
      subject.stub(:create_server => server)
      subject.provision

      subject.error.should eq("All servers failed to provision")
      subject.get_field('cloud_ids').should eq([1])
      subject.get_field('test_ids').should eq([1])
      subject.get_field('cloud_ips').should be_nil
      subject.get_field('test_ips').should be_nil
    end

    it 'should not fail if some servers fail to start' do
      subject.stub(:workitem => {"fields" => fields.merge({"number_of_vms" => 2})})

      connection = double("connection", :servers => [])
      Fog::Compute.stub(:new => connection)
      server1 = mock_server_basic(1, "test 1")
      server1.stub("ready?").and_return(true)
      server1.stub(:public_ip_address).and_return(nil)
      server2 = mock_server(2, "test 2")
      subject.should_receive(:create_server).and_return(server1, server2)
      subject.provision

      subject.error.should be_nil
      subject.get_field('cloud_ids').should eq([1,2])
      subject.get_field('test_ids').should eq([1,2])
      subject.get_field('cloud_ips').should eq(["192.168.1.2"])
      subject.get_field('test_ips').should eq(["192.168.1.2"])
      subject.get_field('cloud_names').should eq(["test 2"])
      subject.get_field('test_names').should eq(["test 2"])
      subject.get_field('test_hostname').should eq("myhostname")
      subject.get_field('test_username').should eq("myusername")
      subject.get_field('test_password').should eq("mypassword")
    end

    it 'should not fail if some servers fail to provision' do
      subject.stub(:workitem => {"fields" => fields.merge({"number_of_vms" => 2})})

      connection = double("connection", :servers => [])
      Fog::Compute.stub(:new => connection)
      server1 = mock_server(1, "test 1")
      server2 = mock_server_basic(2, "test 2")
      server2.stub(:public_ip_address => '192.168.1.2')
      failed_ssh = ssh_result
      failed_ssh.status=1
      server2.should_receive(:ssh).once.and_return([failed_ssh])
      subject.should_receive(:create_server).and_return(server1, server2)
      subject.provision

      subject.error.should be_nil
      subject.get_field('cloud_ids').should eq([1,2])
      subject.get_field('test_ids').should eq([1,2])
      subject.get_field('cloud_ips').should eq(["192.168.1.1", "192.168.1.2"])
      subject.get_field('test_ips').should eq(["192.168.1.1", "192.168.1.2"])
    end

    it 'should fail if all servers fail to provision' do
      subject.stub(:workitem => {"fields" => fields.merge({"number_of_vms" => 2})})

      connection = double("connection", :servers => [])
      Fog::Compute.stub(:new => connection)
      server1 = mock_server_basic(1, "test 1")
      server2 = mock_server_basic(2, "test 2")
      server1.stub(:public_ip_address => '192.168.1.1')
      server2.stub(:public_ip_address => '192.168.1.2')
      failed_ssh = ssh_result
      failed_ssh.status=1
      server1.should_receive(:ssh).once.and_return([failed_ssh])
      server2.should_receive(:ssh).once.and_return([failed_ssh])
      subject.should_receive(:create_server).and_return(server1, server2)
      subject.provision

      subject.error.should eq("All servers failed to provision")
      subject.get_field('cloud_ids').should eq([1,2])
      subject.get_field('test_ids').should eq([1,2])
      subject.get_field('cloud_ips').should eq(["192.168.1.1", "192.168.1.2"])
      subject.get_field('test_ips').should eq(["192.168.1.1", "192.168.1.2"])
    end

    it 'should provision a machine with a random name when name is not provided' do
      connection = double("connection", :servers => [])
      subject.stub({:workitem => {"fields" => fields.reject!{ |k, v| k == 'name' }}, :connect => connection})
      subject.should_receive(:create_server).with(connection, /^maestro-[a-z]{5}$/).and_return(mock_server)
      subject.provision
      subject.error.should be_nil
    end

    it 'should provision more than one server when name is not provided' do
      subject.stub(:workitem => {"fields" => fields.merge({"name" => nil, "number_of_vms" => 3})})

      connection = double("connection", :servers => [])
      Fog::Compute.stub(:new => connection)
      subject.should_receive(:create_server).with(connection, /^maestro-[a-z]{5}$/).and_return(
        mock_server(1), mock_server(2), mock_server(3))
      subject.provision

      subject.error.should be_nil
      subject.get_field('cloud_ids').should eq([1,2,3])
      subject.get_field('test_ids').should eq([1,2,3])
    end

    it 'should provision more than one server with random names when name is provided' do
      subject.stub(:workitem => {"fields" => fields.merge({"number_of_vms" => 3})})

      connection = double("connection", :servers => [])
      Fog::Compute.stub(:new => connection)
      subject.should_receive(:create_server).with(connection, /^test-[a-z]{5}$/).and_return(
        mock_server(1), mock_server(2), mock_server(3))
      subject.provision

      subject.error.should be_nil
      subject.get_field('cloud_ids').should eq([1,2,3])
      subject.get_field('test_ids').should eq([1,2,3])
    end

    it 'should fail if ssh is not properly configured' do
      subject.stub(:workitem => {"fields" => fields.reject {|k,v| k=="private_key"}})
      Fog::Compute.stub(:new => double("connection"))
      subject.provision

      subject.error.should eq("private_key, private_key_path or ssh_password are required for SSH")
      subject.get_field('cloud_ids').should be_nil
      subject.get_field('test_ids').should be_nil
    end

    it 'should fail early if ssh key file does not exist' do
      subject.stub(:workitem => {"fields" => fields.reject {|k,v| k=="private_key"}.merge({"private_key_path" => "/blabla"})})
      Fog::Compute.stub(:new => double("connection"))
      subject.provision

      subject.error.should eq("private_key_path does not exist: /blabla")
      subject.get_field('cloud_ids').should be_nil
      subject.get_field('test_ids').should be_nil
    end

    it 'should generate a random name' do
      subject.random_name.should match(/^maestro-[a-z]{5}$/)
      subject.random_name("test").should match(/^test-[a-z]{5}$/)
      s = "test.acme.com"
      subject.random_name(s).should match(/^test-[a-z]{5}\.acme\.com$/)
      subject.random_name(s).should match(/^test-[a-z]{5}\.acme\.com$/)
    end
  end

  describe 'deprovision' do

    let(:fields) {{
        "params" => {"command" => "deprovision"},
        "username" => "do not use",
        "hostname" => "do not use",
        "password" => "do not use",
        "test_username" => @username,
        "test_hostname" => @hostname,
        "test_password" => @password
    }}

    it 'should destroy started servers' do
      server1 = Fog::Compute::Server.new(:id => 1)
      server2 = Fog::Compute::Server.new(:id => 2)
      stubs = [server1, server2]
      subject.stub(:workitem => {"fields" => fields.merge({"test_ids" => stubs.map { |s| s.id }})})
      Fog::Compute.should_receive(:new).with({
        :provider=>"test",
        :test_hostname=>"myhostname",
        :test_username=>"myusername",
        :test_password=>"mypassword"
        }).and_return(double("connection", :servers => stubs))

      stubs.each do |s|
        stubs.should_receive(:get).once.with(s.id).and_return(s)
        s.should_receive(:destroy).once
        s.should_not_receive(:stop)
      end

      subject.deprovision
      subject.error.should be_nil
    end

    it 'should destroy servers by id or name' do
      server1 = Fog::Compute::Server.new(:id => 1)
      server1.stub(:name => "server1")
      server2 = Fog::Compute::Server.new(:id => 2)
      server2.stub(:name => "server2")
      stubs = [server1, server2]
      subject.stub(:workitem => {"fields" => fields.merge({"instance_ids" => ["1", "server2"]})})
      Fog::Compute.should_receive(:new).with({
        :provider=>"test",
        :test_hostname=>"myhostname",
        :test_username=>"myusername",
        :test_password=>"mypassword"
        }).and_return(double("connection", :servers => stubs))

      stubs.should_receive(:get).once.with("1").and_return(server1)
      server1.should_receive(:destroy).once
      server1.should_not_receive(:stop)
      stubs.should_receive(:get).once.with("server2").and_return(nil)
      server2.should_receive(:destroy).once
      server2.should_not_receive(:stop)

      subject.deprovision
      subject.error.should be_nil
    end

    it 'should not fail if no servers were started' do
      subject.stub(:workitem => {"fields" => fields.merge({"rackspace_ids" => []})})

      subject.deprovision
      subject.error.should be_nil
    end

  end
end

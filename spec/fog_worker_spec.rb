# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'fog_worker'
require 'fog/compute/models/server'

describe MaestroDev::FogPlugin::FogWorker, :provider => "test" do

  # a 'test' provider
  class TestWorker < MaestroDev::FogPlugin::FogWorker
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

  # stub implementation of Servers for our 'test' provider
  class Servers < Fog::Collection
    def all
      self
    end
    def get(id)
      find{|s| s.id == id}
    end
  end

  subject { TestWorker.new }

  def mock_server_basic(id, name)
    server = Fog::Compute::Server.new(:id => id)
    server.class.identity("id")
    server.stub({:name => name, "ready?" => true, :reload => true})
    server
  end

  def mock_server(id=1, name="test")
    server = mock_server_basic(id, name)
    server.stub({:public_ip_address => "192.168.1.#{id}"})
    server.should_receive(:username=).with(ssh_user)
    server.should_receive(:private_key_path=).with(nil)
    server.should_receive(:private_key=).with(private_key)
    server.should_receive(:ssh).once.and_return([ssh_result])
    server
  end
  def ssh_result
    r = Fog::SSH::Result.new("ssh command")
    r.status = 0
    r
  end

  let(:hostname) { "myhostname" }
  let(:username) { "myusername" }
  let(:password) { "mypassword" }
  let(:ssh_user) { "johndoe" }
  let(:private_key) { "aaaa" }
  let(:servers) { Servers.new }
  let(:connection) { double(:connection, :servers => servers) }

  before do
    subject.stub(:workitem => {"fields" => fields})
    Fog::Compute.stub(:new => connection)
  end

  describe 'provision' do

    let(:fields) {{
        "name" => "test",
        "hostname" => hostname,
        "username" => username,
        "password" => password,
        "params" => {"command" => "provision"},
        "ssh_user" => ssh_user,
        "ssh_commands" => ["hostname"],
        "private_key" => private_key
    }}

    context 'when provisioning a server' do
      before do
        subject.should_receive(:create_server).with(connection, "test").and_return(mock_server)
        subject.provision
      end

      its(:error) { should be_nil }
      it { expect(field('cloud_ids')).to eq([1]) }
      it { expect(field('test_ids')).to eq([1]) }
      it { expect(field('cloud_ips')).to eq(["192.168.1.1"]) }
      it { expect(field('test_ips')).to eq(["192.168.1.1"]) }
      it { expect(field('cloud_names')).to eq(["test"]) }
      it { expect(field('test_names')).to eq(["test"]) }
      it { expect(field('test_hostname')).to eq("myhostname") }
      it { expect(field('test_username')).to eq("myusername") }
      it { expect(field('test_password')).to eq("mypassword") }
    end

    context 'when provisioning several servers' do
      let(:fields) { super.merge({"number_of_vms" => 3}) }

      before do
        server1 = mock_server(1, "test 1")
        server2 = mock_server(2, "test 2")
        server3 = mock_server(3, "test 3")
        subject.should_receive(:create_server).with(connection, /^test-[a-z]{5}$/).and_return(server1, server2, server3)
        subject.provision
      end

      its(:error) { should be_nil }
      it { expect(field('cloud_ids')).to eq([1, 2, 3]) }
      it { expect(field('test_ids')).to eq([1, 2, 3]) }
      it { expect(field('cloud_ips')).to eq(["192.168.1.1", "192.168.1.2", "192.168.1.3"]) }
      it { expect(field('test_ips')).to eq(["192.168.1.1", "192.168.1.2", "192.168.1.3"]) }
      it { expect(field('cloud_names')).to eq(["test 1", "test 2", "test 3"]) }
      it { expect(field('test_names')).to eq(["test 1", "test 2", "test 3"]) }
      it { expect(field('test_hostname')).to eq("myhostname") }
      it { expect(field('test_username')).to eq("myusername") }
      it { expect(field('test_password')).to eq("mypassword") }
    end

    # in Rackspace v2 cloud servers may be ready but not have a public ip yet
    context 'when waiting for public ip' do
      let(:ip) { '192.168.1.1' }
      before do
        server = mock_server_basic(1, "test")
        server.stub("ready?").and_return(true)
        server.should_receive(:ssh).once.and_return([ssh_result])
        server.stub(:public_ip_address).and_return(nil, nil, ip)
        subject.stub(:create_server => server)
        subject.provision
      end

      its(:error) { should be_nil }
      it { expect(field('cloud_ids')).to eq([1]) }
      it { expect(field('test_ids')).to eq([1]) }
      it { expect(field('cloud_ips')).to eq([ip]) }
      it { expect(field('test_ips')).to eq([ip]) }
    end

    # in mCloud, servers don't have a public ip assigned automatically.
    context 'when told not to wait for public ip' do
      let(:fields) { super.merge({"wait_for_public_ip" => false}).reject{ |k, v| k == 'ssh_commands' } }

      before do
        server = mock_server_basic(1, "test")
        server.stub("ready?").and_return(true)
        server.stub(:public_ip_address).and_return(nil)
        subject.stub(:create_server => server)
        subject.provision
      end

      its(:error) { should be_nil }
      it { expect(field('cloud_ids')).to eq([1]) }
      it { expect(field('test_ids')).to eq([1]) }
      it { expect(field('cloud_ips')).to be_nil }
    end

    context 'when server does not have public ip' do
      before do
        server = mock_server_basic(1, "test")
        server.stub("ready?").and_return(true)
        server.stub(:public_ip_address).and_return(nil)
        subject.stub(:create_server => server)
        subject.provision
      end

      it "fields should be set" do # timeouts makes this spec slow
        expect(subject.error).to eq("All servers failed to provision")
        expect(field('cloud_ids')).to eq([1])
        expect(field('test_ids')).to eq([1])
        expect(field('cloud_ips')).to be_nil
        expect(field('test_ips')).to be_nil
      end
    end

    context 'when some servers fail to start' do
      let(:fields) { super.merge({"number_of_vms" => 2}) }

      before do
        server1 = mock_server_basic(1, "test 1")
        server1.stub("ready?").and_return(true)
        server1.stub(:public_ip_address).and_return(nil)
        server2 = mock_server(2, "test 2")
        subject.should_receive(:create_server).and_return(server1, server2)
        subject.provision
      end

      it "fields should be set" do # timeouts makes this spec slow
        expect(subject.error).to be_nil
        expect(field('cloud_ids')).to eq([1,2])
        expect(field('test_ids')).to eq([1,2])
        expect(field('cloud_ips')).to eq(["192.168.1.2"])
        expect(field('test_ips')).to eq(["192.168.1.2"])
        expect(field('cloud_names')).to eq(["test 2"])
        expect(field('test_names')).to eq(["test 2"])
        expect(field('test_hostname')).to eq("myhostname")
        expect(field('test_username')).to eq("myusername")
        expect(field('test_password')).to eq("mypassword")
      end
    end

    context 'when some servers fail to provision' do
      let(:fields) { super.merge({"number_of_vms" => 2}) }

      before do
        server1 = mock_server(1, "test 1")
        server2 = mock_server_basic(2, "test 2")
        server2.stub(:public_ip_address => '192.168.1.2')
        failed_ssh = ssh_result
        failed_ssh.status=1
        server2.should_receive(:ssh).once.and_return([failed_ssh])
        subject.should_receive(:create_server).and_return(server1, server2)
        subject.provision
      end

      its(:error) { should be_nil }
      it { expect(field('cloud_ids')).to eq([1,2]) }
      it { expect(field('test_ids')).to eq([1,2]) }
      it { expect(field('cloud_ips')).to eq(["192.168.1.1", "192.168.1.2"]) }
      it { expect(field('test_ips')).to eq(["192.168.1.1", "192.168.1.2"]) }
    end

    context 'when all servers fail to provision' do
      let(:fields) { super.merge({"number_of_vms" => 2}) }

      before do
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
      end

      its(:error) { should eq("All servers failed to provision") }
      it { expect(field('cloud_ids')).to eq([1,2]) }
      it { expect(field('test_ids')).to eq([1,2]) }
      it { expect(field('cloud_ips')).to eq(["192.168.1.1", "192.168.1.2"]) }
      it { expect(field('test_ips')).to eq(["192.168.1.1", "192.168.1.2"]) }
    end

    context 'when name is not provided should provision a machine with a random name' do
      let(:fields) { super.reject{ |k, v| k == 'name' } }
      before do
        subject.should_receive(:create_server).with(connection, /^maestro-[a-z]{5}$/).and_return(mock_server)
        subject.provision
      end
      its(:error) { should be_nil }
    end

    context 'when provisioning more than one server and name is not provided' do
      let(:fields) { super.merge({"name" => nil, "number_of_vms" => 3}) }

      before do
        subject.should_receive(:create_server).with(connection, /^maestro-[a-z]{5}$/).and_return(
          mock_server(1), mock_server(2), mock_server(3))
        subject.provision
      end

      its(:error) { should be_nil }
      it { expect(field('cloud_ids')).to eq([1,2,3]) }
      it { expect(field('test_ids')).to eq([1,2,3]) }
    end

    context 'when provisioning more than one server and name is provided' do
      let(:fields) { super.merge({"number_of_vms" => 3}) }

      before do
        subject.should_receive(:create_server).with(connection, /^test-[a-z]{5}$/).and_return(
          mock_server(1), mock_server(2), mock_server(3))
        subject.provision
      end

      its(:error) { should be_nil }
      it { expect(field('cloud_ids')).to eq([1,2,3]) }
      it { expect(field('test_ids')).to eq([1,2,3]) }
    end

    context 'when ssh is not properly configured' do
      let(:fields) { super.reject {|k,v| k=="private_key"} }

      before do
        Fog::Compute.stub(:new => double("connection"))
        subject.provision
      end

      its(:error) { should eq("private_key, private_key_path or ssh_password are required for SSH") }
      it { expect(field('cloud_ids')).to be_nil }
      it { expect(field('test_ids')).to be_nil }
    end

    context 'when ssh key file does not exist' do
      let(:fields) { super.reject {|k,v| k=="private_key"}.merge({"private_key_path" => "/blabla"}) }
      before { subject.provision }
      its(:error) { should eq("private_key_path does not exist: /blabla") }
      it { expect(field('cloud_ids')).to be_nil }
      it { expect(field('test_ids')).to be_nil }
    end

    context 'when generating a random name' do
      it { subject.random_name.should match(/^maestro-[a-z]{5}$/) }
      it { subject.random_name("test").should match(/^test-[a-z]{5}$/) }
      it "should work if run twice" do
        s = "test.acme.com"
        subject.random_name(s).should match(/^test-[a-z]{5}\.acme\.com$/)
        subject.random_name(s).should match(/^test-[a-z]{5}\.acme\.com$/)
      end
    end
  end

  describe 'deprovision' do

    let(:fields) {{
        "params" => {"command" => "deprovision"},
        "username" => "do not use",
        "hostname" => "do not use",
        "password" => "do not use",
        "test_username" => username,
        "test_hostname" => hostname,
        "test_password" => password
    }}

    let(:server1) do
      s = Fog::Compute::Server.new(:id => 1)
      s.stub(:name => "server1", :id => 1)
      s
    end
    let(:server2) do
      s = Fog::Compute::Server.new(:id => 2)
      s.stub(:name => "server2", :id => 2)
      s
    end
    let(:servers) do
      s = Servers.new
      s << server1
      s << server2
      s
    end

    it { expect(servers.size).to eq(2) }

    context 'when servers were started' do

      before do
        Fog::Compute.should_receive(:new).with({
          :provider => "test",
          :test_hostname => hostname,
          :test_username => username,
          :test_password => password
        }).and_return(connection)
      end

      context 'when normally started' do
        let(:fields) { super.merge({"test_ids" => servers.map { |s| s.id }}) }

        before do
          servers.each do |s|
            servers.should_receive(:get).once.with(s.id).and_return(s)
            s.should_receive(:destroy).once
            s.should_not_receive(:stop)
          end
          subject.deprovision
        end

        its(:error) { should be_nil }
      end

      context 'when destroying servers by id or name' do
        let(:fields) { super.merge({"instance_ids" => ["1", "server2"]}) }

        before do
          servers.should_receive(:get).once.with("1").and_return(server1)
          server1.should_receive(:destroy).once
          server1.should_not_receive(:stop)
          servers.should_receive(:get).once.with("server2").and_return(nil)
          server2.should_receive(:destroy).once
          server2.should_not_receive(:stop)
          subject.deprovision
        end

        its(:error) { should be_nil }
      end
    end

    context 'when no servers were started' do
      let(:fields) { super.merge({"rackspace_ids" => []}) }
      before do
        Fog::Compute.should_receive(:new).never
        subject.deprovision
      end
      its(:error) { should be_nil }
    end

    context 'when deprovisioning a server already deleted' do
      let(:fields) { super.merge({"instance_ids" => [999]}) }

      before do
        subject.should_receive(:delete_record).with("machine", {"instance_id" => 999, "type" => "test"})
        subject.deprovision
      end

      its(:error) { should be_nil }
    end

  end
end

# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'v_sphere_worker'

# connection.servers output in vSphere 5 test is a bit different than the Fog test data
#
# [  <Fog::Compute::Vsphere::Server
#     id="524de983-d2d5-b55c-5fb7-bcd1e9a9f586",
#     name="VMware vCenter Server Appliance",
#     uuid="564db793-79af-3dc2-a012-2615c76cf8c3",
#     instance_uuid="524de983-d2d5-b55c-5fb7-bcd1e9a9f586",
#     hostname=nil,
#     operatingsystem=nil,
#     ipaddress=nil,
#     power_state="poweredOff",
#     tools_state="toolsNotRunning",
#     tools_version="guestToolsUnmanaged",
#     mac_addresses={"Network adapter 1"=>"00:0c:29:6c:f8:c3"},
#     hypervisor="localhost.localdomain",
#     is_a_template=false,
#     connection_state="connected",
#     mo_ref="1",
#     path="/ha-folder-root/ha-datacenter/vm",
#     memory_mb=8192,
#     cpus=2
#   >,
#    <Fog::Compute::Vsphere::Server
#     id="52c96748-e203-669e-e104-b2d7b11179e8",
#     name="vm-669",
#     uuid="564dbd30-e464-7acc-f5d1-007aaa95b87a",
#     instance_uuid="52c96748-e203-669e-e104-b2d7b11179e8",
#     hostname=nil,
#     operatingsystem=nil,
#     ipaddress=nil,
#     power_state="poweredOn",
#     tools_state="toolsNotInstalled",
#     tools_version="guestToolsNotInstalled",
#     mac_addresses={"Network adapter 1"=>"00:0c:29:95:b8:7a"},
#     hypervisor="localhost.localdomain",
#     is_a_template=false,
#     connection_state="connected",
#     mo_ref="4",
#     path="/ha-folder-root/ha-datacenter/vm",
#     memory_mb=512,
#     cpus=1
#   >]

describe MaestroDev::VSphereWorker, :provider => "vsphere" do

  def connect
    Fog::Compute.new(
      :provider => "vsphere",
      :vsphere_username => @username,
      :vsphere_password => @password,
      :vsphere_server => @host)
  end

  before(:each) do
    @worker = MaestroDev::VSphereWorker.new
    @worker.stub(:send_workitem_message)

    # mock
    @host = "localhost"
    @datacenter = "Solutions"
    @username = 'root'
    @password = 'password'
    @template_name = 'rhel64'
    @vm_name = 'new vm'

    @connection = connect

    # test
    # @host = "172.16.184.129"
    # @datacenter = 'ha-datacenter'
    # @username = 'root'
    # @password = 'vagrant'
    # @template_name = 'test template'
    # @vm_name = 'test 2'
  end

  describe 'provision' do

    before(:each) do
      @fields = {
        "params" => {"command" => "provision"},
        "host" => @host,
        "datacenter" => @datacenter,
        "username" => @username,
        "password" => @password,
        "template_name" => @template_name,
        "name" => "xxx"
      }

      # @vms = @connection.list_virtual_machines
      # @connection.should_receive(:list_virtual_machines).with({}).and_return(@vms)
    end

    it 'should provision a machine' do
      wi = Ruote::Workitem.new({"fields" => @fields})

      # Fog.Mock is not complete
      @connection.should_receive(:vm_clone).with({
        "name" => "xxx",
        "path" => "/Datacenters/Solutions/#{@template_name}",
        "poweron" => true,
        "wait" => false
      }).and_return({
        'vm_ref'   => 'vm-715',
        'task_ref' => 'task-1234',
      })

      @worker.stub(:workitem => wi.to_h, :connect => @connection)
      @worker.provision

      wi.fields['__error__'].should eq(nil)
      wi.fields['vsphere_ids'].should eq(["5032c8a5-9c5e-ba7a-3804-832a03e16381"])
    end

    it 'should fail when template does not exist' do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"template_name" => "doesnotexist"})})

      @worker.stub(:workitem => wi.to_h, :connect => @connection)
      @worker.provision
      wi.fields['__error__'].should eq("VM template '/Datacenters/Solutions/doesnotexist' not found")
    end

    it 'should print an error if template fails to clone' do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"template_name" => "another"})})
      @worker.stub(:workitem => wi.to_h, :connect => @connection)
      @connection.should_receive(:vm_clone).with({
        "name" => "xxx",
        "path" => "/Datacenters/Solutions/another",
        "poweron" => true,
        "wait" => false
      }).and_raise(RbVmomi::Fault.new("message", "fault"))
      @worker.provision

      wi.fields['__error__'].should match(%r[^Error cloning template '/Datacenters/Solutions/another' as 'xxx'.*message\n])
    end
  end

  describe 'deprovision' do

    before(:each) do
      @fields = {
        "params" => {"command" => "deprovision"},
        "vsphere_host" => @host,
        "vsphere_username" => @username,
        "vsphere_password" => @password,
        "vsphere_ids" => ["5029c440-85ee-c2a1-e9dd-b63e39364603", "502916a3-b42e-17c7-43ce-b3206e9524dc"],
      }
    end

    it 'should deprovision a machine' do
      wi = Ruote::Workitem.new({"fields" => @fields})
      @worker.stub(:workitem => wi.to_h, :connect => @connection)

      stubs = @connection.servers.find_all {|s| @fields["vsphere_ids"].include?(s.id)}
      stubs.size.should == 2
      servers = double("servers")
      @connection.stub(:servers => servers)

      stubs.each do |s|
        servers.should_receive(:get).once.with(s.id).and_return(s)
        s.stub(:ready? => false)
        s.should_not_receive(:stop)
        s.should_receive(:destroy).once
      end

      @worker.deprovision
      wi.fields['__error__'].should eq(nil)
    end

    it 'should stop machine before deprovisioning' do
      id = "502916a3-b42e-17c7-43ce-b3206e9524dc"
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"vsphere_ids" => [id]})})
      @worker.stub(:workitem => wi.to_h, :connect => @connection)

      stub = @connection.servers.find {|s| id == s.id}
      stub.should_not be_nil
      servers = double("servers")
      @connection.stub(:servers => servers)

      servers.should_receive(:get).with(id).and_return(stub)
      stub.ready?.should be_true
      stub.should_receive(:destroy).once

      @worker.deprovision
      wi.fields['__error__'].should eq(nil)
    end
  end
end

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

describe MaestroDev::VSphereWorker, :provider => "vsphere", :skip => true do

  def connect
    Fog::Compute.new(
      :provider => "vsphere",
      :vsphere_username => @username,
      :vsphere_password => @password,
      :vsphere_server => @host)
  end

  before(:each) do
    @worker = MaestroDev::VSphereWorker.new
    @worker.stub(:write_output)

    # mock
    @host = "localhost"
    @datacenter = "Solutions"
    @username = 'root'
    @password = 'password'
    @template_name = 'centos56gm'
    @vm_name = 'new vm'

    # test
    # @host = "172.16.184.129"
    # @datacenter = 'ha-datacenter'
    # @username = 'root'
    # @password = 'vagrant'
    # @template_name = 'test template'
    # @vm_name = 'test 2'
  end

  describe 'provision' do

    before(:all) do
      @fields = {
        "params" => {"command" => "provision"},
        "host" => @host,
        "datacenter" => @datacenter,
        "username" => @username,
        "password" => @password,
        "template_name" => @template_name,
        "name" => "xxx",
        "ssh_commands" => ["hostname"]
      }
    end

    it 'should provision a machine' do
      wi = Ruote::Workitem.new({"fields" => @fields})
      @worker.stub(:workitem => wi.to_h)
      @worker.provision

      wi.fields['__error__'].should eq(nil)
      wi.fields['vsphere_server'].should eq(@host)
      wi.fields['vsphere_username'].should eq(@username)
      wi.fields['vsphere_password'].should eq(@password)
      wi.fields['vsphere_ids'].should eq(["50323f93-6835-1178-8b8f-9e2109890e1a"])
    end

    it 'should fail when template does not exist' do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"template_name" => "doesnotexist"})})

      @worker.stub(:workitem => wi.to_h)
      @worker.provision
      wi.fields['__error__'].should eq("VM template '/Datacenters/Solutions/doesnotexist' not found")
    end
  end

  describe 'deprovision' do

    before(:all) do
      @fields = {
        "params" => {"command" => "deprovision"},
        "vsphere_host" => @host,
        "vsphere_username" => @username,
        "vsphere_password" => @password,
        "vsphere_ids" => ["50323f93-6835-1178-8b8f-9e2109890e1a", "5257dee8-050c-cbcd-ae25-db0e582ab530"],
      }
    end

    it 'should deprovision a machine' do
      wi = Ruote::Workitem.new({"fields" => @fields})
      @worker.stub(:workitem => wi.to_h)

      connection = connect
      stubs = connection.servers.find_all {|s| @fields["vsphere_ids"].include?(s.id)}

      servers = double("servers")
      connection.stub(:servers => servers)
      @worker.stub(:connect => connection)

      stubs.each do |s|
        servers.should_receive(:get).once.with(s.id).and_return(s)
        s.ready?.should == false
        s.should_not_receive(:stop)
        s.should_receive(:destroy).once
      end

      @worker.deprovision
      wi.fields['__error__'].should eq(nil)
    end

    it 'should stop machine before deprovisioning' do
      id = "5032c8a5-9c5e-ba7a-3804-832a03e16381"
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"vsphere_ids" => [id]})})
      @worker.stub(:workitem => wi.to_h)

      connection = connect
      stub = connection.servers.find {|s| id == s.id}

      servers = double("servers")
      connection.stub(:servers => servers)
      @worker.stub(:connect => connection)

      servers.should_receive(:get).with(id).and_return(stub)
      stub.ready?.should == true
      stub.should_receive(:destroy).once

      @worker.deprovision
      wi.fields['__error__'].should eq(nil)
    end
  end
end

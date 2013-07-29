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

describe MaestroDev::FogPlugin::VSphereWorker, :provider => "vsphere" do

  let(:connection) {
    Fog::Compute.new(
      :provider => "vsphere",
      :vsphere_username => username,
      :vsphere_password => password,
      :vsphere_server => host)
  }

  let(:host) { "localhost" }
  let(:username) { 'root' }
  let(:password) { 'password' }
  let(:datacenter) { 'Solutions' }
  let(:template_path) { 'rhel64' }
  let(:vm_name) { 'new vm' }
  let(:destination_folder) { "newfolder" }

  before do
    subject.workitem = {"fields" => fields}
    subject.stub(:connect => connection)
  end

  describe 'provision' do

    let(:fields) {{
      "params" => {"command" => "provision"},
      "host" => host,
      "username" => username,
      "password" => password,
      "datacenter" => datacenter,
      "template_path" => template_path,
      "destination_folder" => destination_folder,
      "name" => "xxx"
    }}

    context 'when provisioning a machine' do

      before do
        # Fog.Mock is not complete
        connection.should_receive(:vm_clone).with({
          "datacenter" => datacenter,
          "name" => "xxx",
          "template_path" => template_path,
          "dest_folder" => destination_folder,
          "poweron" => true,
          "wait" => false
        }).and_return({
          'vm_ref'   => 'vm-715',
          'new_vm'   => {'id' => 'vm-715'},
          'task_ref' => 'task-1234',
        })

        # vm is returned without ip in mocks, so stub around it
        vm = connection.get_virtual_machine('vm-715')
        vm[:public_ip_address] = vm[:ipaddress]
        connection.stub(:get_virtual_machine).with('5032c8a5-9c5e-ba7a-3804-832a03e16381').and_call_original
        connection.stub(:get_virtual_machine).with('5032c8a5-9c5e-ba7a-3804-832a03e16381', nil).and_call_original
        connection.should_receive(:get_virtual_machine).with('vm-715', nil).and_return(vm)

        subject.stub(:workitem => {"fields" => fields}, :connect => connection)
        subject.provision
      end

      its(:error) { should be_nil }
      it { expect(subject.workitem[Maestro::MaestroWorker::OUTPUT_META]).to include(
        "Server 'jefftest' 5032c8a5-9c5e-ba7a-3804-832a03e16381 started with public ip '192.168.100.187' and private ip ''") }
      it { expect(field('vsphere_ids')).to eq(["5032c8a5-9c5e-ba7a-3804-832a03e16381"]) }
    end

    context 'when template does not exist' do
      let(:fields) { super.merge({"template_path" => "doesnotexist"}) }
      before { subject.provision }
      its(:error) { should eq("VM template 'doesnotexist': Could not find VM template") }
    end

    context 'when template fails to clone' do
      let(:fields) { super.merge({"template_path" => "another"}) }

      before do
        connection.should_receive(:vm_clone).with({
          "datacenter" => datacenter,
          "name" => "xxx",
          "template_path" => "another",
          "dest_folder" => destination_folder,
          "poweron" => true,
          "wait" => false
        }).and_raise(RbVmomi::Fault.new("message", "fault"))
        subject.provision
      end

      its(:error) { should match(%r[^Error cloning template 'another' as 'newfolder/xxx'.*message\n]) }
    end
  end

  describe 'deprovision' do

    let(:fields) {{
      "params" => {"command" => "deprovision"},
      "vsphere_host" => host,
      "vsphere_username" => username,
      "vsphere_password" => password,
      "vsphere_ids" =>  ids,
      "__context_outputs__" => context_outputs('vsphere', ids),
    }}
    let(:ids) { ['5029c440-85ee-c2a1-e9dd-b63e39364603', '502916a3-b42e-17c7-43ce-b3206e9524dc'] }

    context 'when machines have been created' do
      before do
        stubs = connection.servers.find_all {|s| fields["vsphere_ids"].include?(s.id)}
        stubs.size.should == 2
        servers = double("servers")
        connection.stub(:servers => servers)

        stubs.each do |s|
          servers.should_receive(:get).once.with(s.id).and_return(s)
          s.stub(:ready? => false)
          s.should_not_receive(:stop)
          s.should_receive(:destroy).once
        end

        subject.deprovision
      end
      its(:error) { should be_nil }
    end

    context 'when machine is running' do
      let(:id) { '502916a3-b42e-17c7-43ce-b3206e9524dc' }
      let(:fields) { super.merge({"vsphere_ids" => [id]}) }

      before do
        stub = connection.servers.find {|s| id == s.id}
        stub.should_not be_nil
        servers = double('servers')
        connection.stub(:servers => servers)

        servers.should_receive(:get).with(id).and_return(stub)
        stub.ready?.should be_true
        stub.should_receive(:destroy).once

        subject.deprovision
      end

      its(:error) { should be_nil }
    end
  end
end

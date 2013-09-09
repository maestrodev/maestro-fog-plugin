# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'v_sphere_worker'

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
    connection.reset_data
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
      before { subject.provision }
      its(:error) { should be_nil }
      it { expect(subject.workitem[Maestro::MaestroWorker::OUTPUT_META]).to match(
        /Server 'xxx' #{uuid_regex} started with public ip '192.168.100.184' and private ip ''/) }
      it { expect(field('vsphere_ids').to_s).to match(/^\["#{uuid_regex}"\]$/) }
    end

    context 'when template does not exist' do
      before { subject.provision }
      let(:fields) { super().merge({"template_path" => "doesnotexist"}) }
      its(:error) { should eq("VM template 'doesnotexist': Could not find VM template") }
    end

    context 'when template fails to clone' do
      let(:fields) { super().merge({"template_path" => "another"}) }

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

      # jruby and c-ruby raise different exception messages
      its(:error) { should match(%r[^Error cloning template 'another' as 'newfolder/xxx'.*[Ff]ault]) }
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
      let(:fields) { super().merge({"vsphere_ids" => [id]}) }

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

  def uuid_regex
    "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
  end

end

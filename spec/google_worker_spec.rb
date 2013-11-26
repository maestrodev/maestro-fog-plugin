# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'google_worker'

describe MaestroDev::Plugin::GoogleWorker, :provider => "google" do

  let(:connection) { Fog::Compute.new(
    :provider => "google",
    :google_project => project,
    :google_client_email => client_email,
    :google_key_location => key_location)
  }

  let(:project) { 'test' }
  let(:client_email) { 'john@gmail.com' }
  let(:key_location) { './key.p12' }
  let(:zone_name) { "us-central1-a" }
  let(:machine_type) { "n1-standard-1" }
  let(:image_name) { "centos-6-v20130813" }

  let(:fields) {{
    "project" => project,
    "client_email" => client_email,
    "key_location" => key_location
  }}

  before do
    connection.class.reset
    subject.workitem = {"fields" => fields}
    subject.stub(:connect => connection)
  end

  describe 'provision' do

    let(:fields) { super().merge({
      "name" => "xxx",
      "image_name" => image_name,
      "machine_type" => machine_type,
      "zone_name" => zone_name,
      "public_key" => "ssh-rsa xxxx",
      "username" => "support"
    })}

    context 'when provisioning a machine' do
      before { subject.provision }
      its(:error) { should be_nil }
      it { expect(subject.workitem[Maestro::MaestroWorker::OUTPUT_META]).to match(
        /Server 'xxx' xxx started with public ip '\d+\.\d+\.\d+\.\d+' and private ip '\d+\.\d+\.\d+\.\d+'/) }
      it { expect(field('google_ids')).to eq(["xxx"]) }
      it { expect(field('__context_outputs__')['servers']).to eq([{
        "id" => "xxx",
        "name" => "xxx",
        "ip" => subject.get_field("google_ips").first,
        "ipv4" => subject.get_field("google_ips").first,
        "image" => "https://www.googleapis.com/compute/#{connection.api_version}/projects/centos-cloud/global/images/#{image_name}",
        "flavor" => "https://www.googleapis.com/compute/#{connection.api_version}/projects/#{project}/zones/#{zone_name}/machineTypes/#{machine_type}",
        "provider" => "google"
      }]), subject.output }
    end
  end

  describe 'deprovision' do
    let(:servers) {
      (1..2).map do |i|
        connection.servers.create(
          :name => "server#{i}", :image_name => image_name, :machine_type => machine_type, :zone_name => zone_name)
      end
    }
    let(:fields) { super().merge({
      "google_ids" => servers.map{|s| s.identity}
    })}
    let(:stop_states) { ["STOPPED", "STOPPING", "TERMINATED"] }

    before do
      servers # force creation
      # expect_any_instance_of(Fog::Compute::Google::Server).to receive(:destroy).and_call_original
      subject.deprovision
    end

    context 'when deprovisioning a machine' do
      its(:error) { should be_nil }
      it { expect(subject.output).to match(
        %r{Deprovisioned VM with id/name 'server1'.*Deprovisioned VM with id/name 'server2'.*Maestro google deprovision complete!}m
      ) }
      it { expect(stop_states).to include(connection.servers.get("server1").state) }
      it { expect(stop_states).to include(connection.servers.get("server2").state) }
    end

    context 'when deprovisioning a machine with persistent disk' do
      let(:disks) { [connection.disks.create(
        :name => 'disk1', :size_gb => 10, :zone_name => zone_name, :source_image => image_name
      )] }
      let(:servers) { [connection.servers.create(
        :name => "server3", :machine_type => machine_type, :zone_name => zone_name, :kernel => 'gce-no-conn-track-v20130813', :disks => [ disks.first.get_as_boot_disk ]
      )] }

      context 'and destroy_disks is not set' do
        its(:error) { should be_nil }
        it { expect(connection.disks.size).to eq(1) }
        it { expect(subject.output).not_to include("Deleting") }
      end

      context 'and destroy_disks is true' do
        let(:fields) { super().merge({"destroy_disks" => true})}
        its(:error) { should be_nil }
        it { expect(connection.disks).to eq([]) }
        it { expect(subject.output).to match(/Deleting disks: \["disk1"\]...done/m) }
      end
    end
  end
end

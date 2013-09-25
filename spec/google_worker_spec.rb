# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'google_worker'

describe MaestroDev::FogPlugin::GoogleWorker, :provider => "google", :disabled => true do # needs fog 1.16.0+

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
        /Server 'xxx' xxx started with public ip '.*' and private ip '.*'/) }
      it { expect(field('google_ids')).to eq(["xxx"]) }
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
      "google_ids" => ["server1","server2"]
    })}

    context 'when deprovisioning a machine' do
      before do
        servers # force creation
        subject.deprovision
      end
      its(:error) { should be_nil }
      it { expect(subject.workitem[Maestro::MaestroWorker::OUTPUT_META]).to match(
        %r[Deprovisioning VM with id/name 'server1'\nDeprovisioning VM with id/name 'server2'\nMaestro google deprovision complete!]) }
    end
  end
end

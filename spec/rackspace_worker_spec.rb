# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'rackspace_worker'

shared_examples "rackspace" do |version|

  let(:api_key) { "myapi" }
  let(:username) { "johndoe" }
  let(:image_id) { "49" }
  let(:auth_url) { "lon.auth.api.rackspacecloud.com" }

  before do
    subject.stub(:send_workitem_message)
  end

  describe 'provision' do

    let(:fields) {{
      "params" => {"command" => "provision"},
      "username" => username,
      "api_key" => api_key,
      "image_id" => image_id,
      "version" => version
    }}

    before do
      Fog.timeout = 6 # rackspace mock servers take ~4s to be ready
      subject.stub(:workitem => {"fields" => fields})
      subject.provision
    end

    context 'when provisioning a machine' do
      it 'should succed' do
        subject.error.should be_nil
        expect(field('rackspace_api_key')).to eq(api_key)
        expect(field('rackspace_username')).to eq(username)
        expect(field('rackspace_auth_url')).to be_nil
        expect(field('rackspace_ids')).not_to be_empty
        expect(field('rackspace_ids').size).to be 1
      end
    end

    # can't test it with mock
    # it 'should fail when image does not exist', :disabled => true do
    #
    #   subject.stub(:workitem => {"fields" => fields.merge({"image_id" => "999999"})})
    #   subject.provision
    #   its(:error) { should eq("Image id '999999' flavor '1' not found") }
    # end

    context 'when provisioning a machine in europe' do
      let(:fields) { super().merge({"auth_url" => auth_url}) }

      it 'should succed' do
        subject.error.should be_nil
        expect(field('rackspace_api_key')).to eq(api_key)
        expect(field('rackspace_username')).to eq(username)
        expect(field('rackspace_auth_url')).to eq(auth_url)
      end
    end
  end

  describe 'deprovision' do

    let(:connection_opts) {{
      :provider => "rackspace",
      :rackspace_username => username,
      :rackspace_api_key => api_key,
      :version => version
    }}
    let(:connection) { Fog::Compute.new(connection_opts) }

    let(:fields) {{
      "params" => {"command" => "deprovision"},
      "rackspace_username" => username,
      "rackspace_api_key" => api_key,
      "version" => version
    }}

    before do
      subject.stub(:workitem => {"fields" => fields})
    end

    context 'when deprovisioning a machine' do
      let(:stubs) do
        # create 2 servers
        stubs = {}
        (1..2).each do |i|
          s = connection.servers.create
          s.wait_for { ready? }
          stubs[s.identity]=s
        end
        stubs
      end

      let(:fields) { super().merge({"rackspace_ids" => stubs.keys}) }

      before do
        stubs # force creation
        subject.stub(:connect => connection)
        servers = double("servers")
        connection.stub(:servers => servers)

        stubs.values.each do |s|
          servers.should_receive(:get).once.with(s.identity).and_return(s)
          s.ready?.should == true
          s.should_receive(:destroy).once
          s.should_not_receive(:stop)
        end
        subject.deprovision
      end

      its(:error) { should be_nil }
    end
  end
end

describe MaestroDev::FogPlugin::RackspaceWorker, :provider => "rackspace" do
  context "version 1" do
    it_behaves_like "rackspace", nil
  end
  context "version 2", :disabled => true do
    it_behaves_like "rackspace", "v2"
  end
end

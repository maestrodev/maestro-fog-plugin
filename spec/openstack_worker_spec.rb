# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'openstack_worker'

describe MaestroDev::OpenstackWorker, :provider => "openstack" do

  def connect
    keystone = Fog::Identity.new(
      :provider           => 'openstack',
      :openstack_auth_url => @auth_url,
      :openstack_username => @username,
      :openstack_api_key  => @api_key)
    Fog::Compute.new(
      :provider => "openstack",
      :openstack_tenant => @tenant,
      :openstack_auth_url => @auth_url,
      :openstack_username => @username,
      :openstack_api_key => @api_key)
  end

  before(:each) do
    @worker = MaestroDev::OpenstackWorker.new
    @worker.stub(:send_workitem_message)
    @api_key = "myapi"
    @username = "johndoe"
    @image_id = "abc-123-456-789"
    @auth_url = "http://example.openstack.org:35357/v2.0/tokens"
    @tenant = "demo"
    @name ="Spec"
    @flavor_id = "2"
    @security_group ="default"
    @key_name ="default"
  end

  describe 'provision' do

    before(:each) do
      @fields = {
        "params" => {"command" => "provision"},
        "username" => @username,
        "api_key" => @api_key,
        "image_id" => @image_id,
        "auth_url" => @auth_url,
        "tenant" => @tenant,
        "flavor_id" => @flavor_id,
        "name" => @name,
        "key_name" => @key_name,
        "security_group" => @security_group
      }
    end

    it 'should provision a machine', :skip => true do
      wi = Ruote::Workitem.new({"fields" => @fields})
      @worker.stub(:workitem => wi.to_h)
      @worker.provision

      wi.fields['__error__'].should be nil
      wi.fields['openstack_api_key'].should eq(@api_key)
      wi.fields['openstack_username'].should eq(@username)
      wi.fields['openstack_auth_url'].should eq(@auth_url)
      wi.fields['openstack_tenant'].should eq(@tenant)
      wi.fields['openstack_ids'].should_not be_empty
      wi.fields['openstack_ids'].size.should be 1
    end

    # can't test it with mock
    # it 'should fail when image does not exist', :skip => true do
    #   wi = Ruote::Workitem.new({"fields" => @fields.merge({"image_id" => 999999})})
    #
    #   @worker.stub(:workitem => wi.to_h)
    #   @worker.provision
    #   wi.fields['__error__'].should eq("Image id '999999' flavor '1' not found")
    # end

    it 'should provision a machine in a different endpoint', :skip => true do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"auth_url" => @auth_url})})
      @worker.stub(:workitem => wi.to_h)
      @worker.provision

      wi.fields['__error__'].should be nil
      wi.fields['openstack_api_key'].should eq(@api_key)
      wi.fields['openstack_username'].should eq(@username)
      wi.fields['openstack_auth_url'].should eq(@auth_url)
      wi.fields['openstack_tenant'].should eq(@tenant)
    end
  end

  describe 'deprovision' do

    before(:each) do
      @fields = {
        "params" => {"command" => "deprovision"},
        "openstack_username" => @username,
        "openstack_api_key" => @api_key
      }
    end

    it 'should deprovision a machine', :skip => true do
      connection = connect

      # create 2 servers
      stubs = {}
      (1..2).each do |i|

        s = connection.servers.create(
          :flavor_ref => @flavor_id,
          :image_ref => @image_id,
          :name => @name)
        s.wait_for { ready? }
        stubs[s.id]=s
      end

      wi = Ruote::Workitem.new({"fields" => @fields.merge({"openstack_ids" => stubs.keys})})
      @worker.stub(:workitem => wi.to_h)
      @worker.stub(:connect => connection)
      servers = double("servers")
      connection.stub(:servers => servers)

      stubs.values.each do |s|
        servers.should_receive(:get).once.with(s.id).and_return(s)
        s.ready?.should == true
        s.should_receive(:destroy).once
        s.should_not_receive(:stop)
      end

      @worker.deprovision
      wi.fields['__error__'].should eq(nil)
    end

  end
end

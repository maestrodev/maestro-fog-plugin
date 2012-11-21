# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'rackspace_worker'

describe MaestroDev::RackspaceWorker, :provider => "rackspace" do

  def connect
    Fog::Compute.new(
      :provider => "rackspace",
      :rackspace_username => @username,
      :rackspace_api_key => @api_key)
  end

  before(:all) do
    @worker = MaestroDev::RackspaceWorker.new

    @api_key = "myapi"
    @username = "johndoe"
    @image_id = "49"
    @auth_url = "lon.auth.api.rackspacecloud.com"
  end

  describe 'provision' do

    before(:all) do
      @fields = {
        "params" => {"command" => "provision"},
        "username" => @username,
        "api_key" => @api_key,
        "image_id" => @image_id
      }
    end

    it 'should provision a machine', :skip => true do
      wi = Ruote::Workitem.new({"fields" => @fields})
      @worker.stub(:workitem => wi.to_h)
      @worker.provision

      wi.fields['__error__'].should be nil
      wi.fields['rackspace_api_key'].should eq(@api_key)
      wi.fields['rackspace_username'].should eq(@username)
      wi.fields['rackspace_auth_url'].should be nil
      wi.fields['rackspace_ids'].should_not be_empty
      wi.fields['rackspace_ids'].size.should be 1
    end

    # can't test it with mock
    # it 'should fail when image does not exist', :skip => true do
    #   wi = Ruote::Workitem.new({"fields" => @fields.merge({"image_id" => "999999"})})
    #
    #   @worker.stub(:workitem => wi.to_h)
    #   @worker.provision
    #   wi.fields['__error__'].should eq("Image id '999999' flavor '1' not found")
    # end

    it 'should provision a machine in europe', :skip => true do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"auth_url" => @auth_url})})
      @worker.stub(:workitem => wi.to_h)
      @worker.provision

      wi.fields['__error__'].should be nil
      wi.fields['rackspace_api_key'].should eq(@api_key)
      wi.fields['rackspace_username'].should eq(@username)
      wi.fields['rackspace_auth_url'].should eq(@auth_url)
    end
  end

  describe 'deprovision' do

    before(:all) do
      @fields = {
        "params" => {"command" => "deprovision"},
        "rackspace_username" => @username,
        "rackspace_api_key" => @api_key
      }
    end

    it 'should deprovision a machine' do
      connection = connect

      # create 2 servers
      stubs = {}
      (1..2).each do |i|
        s = connection.servers.create
        s.wait_for { ready? }
        stubs[s.id]=s
      end

      wi = Ruote::Workitem.new({"fields" => @fields.merge({"rackspace_ids" => stubs.keys})})
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

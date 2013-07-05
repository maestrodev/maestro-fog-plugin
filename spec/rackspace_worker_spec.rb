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

  before(:each) do
    subject.stub(:send_workitem_message)

    @api_key = "myapi"
    @username = "johndoe"
    @image_id = "49"
    @auth_url = "lon.auth.api.rackspacecloud.com"
  end

  describe 'provision' do

    before(:each) do
      @fields = {
        "params" => {"command" => "provision"},
        "username" => @username,
        "api_key" => @api_key,
        "image_id" => @image_id
      }
    end

    it 'should provision a machine' do
      subject.stub(:workitem => {"fields" => @fields})
      subject.provision

      subject.error.should be_nil
      subject.get_field('rackspace_api_key').should eq(@api_key)
      subject.get_field('rackspace_username').should eq(@username)
      subject.get_field('rackspace_auth_url').should be_nil
      subject.get_field('rackspace_ids').should_not be_empty
      subject.get_field('rackspace_ids').size.should be 1
    end

    # can't test it with mock
    # it 'should fail when image does not exist', :skip => true do
    #
    #   subject.stub(:workitem => {"fields" => @fields.merge({"image_id" => "999999"})})
    #   subject.provision
    #   subject.error.should eq("Image id '999999' flavor '1' not found")
    # end

    it 'should provision a machine in europe' do
      subject.stub(:workitem => {"fields" => @fields.merge({"auth_url" => @auth_url})})
      subject.provision

      subject.error.should be_nil
      subject.get_field('rackspace_api_key').should eq(@api_key)
      subject.get_field('rackspace_username').should eq(@username)
      subject.get_field('rackspace_auth_url').should eq(@auth_url)
    end
  end

  describe 'deprovision' do

    before(:each) do
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

      subject.stub(:workitem => {"fields" => @fields.merge({"rackspace_ids" => stubs.keys})})
      subject.stub(:connect => connection)
      servers = double("servers")
      connection.stub(:servers => servers)

      stubs.values.each do |s|
        servers.should_receive(:get).once.with(s.id).and_return(s)
        s.ready?.should == true
        s.should_receive(:destroy).once
        s.should_not_receive(:stop)
      end

      subject.deprovision
      subject.error.should be_nil
    end

  end
end

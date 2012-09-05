# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'openstack_worker'

describe MaestroDev::OpenstackWorker do

  def connect
    Fog::Compute.new(
      :provider => "openstack",
      :openstack_username => @username,
      :openstack_api_key => @api_key)
  end

  before(:all) do
    Fog.mock!
    @worker = MaestroDev::OpenstackWorker.new

    @api_key = "myapi"
    @username = "johndoe"
    @image_id = "abc-123-def-456"
    @auth_url = "http://demo.openstack.org:35357/v2.0/tokens"
    @flavor_id = "2"
    @name = "spec"
    @key_name = "default"
    @sec_group = "default"
    @tenant = "demo"

  end

  describe 'provision' do

    before(:all) do
      @fields = {
        "params" => {"command" => "provision"},
        "username" => @username,
        "api_key" => @api_key,
        "image_id" => @image_id,
        "name" => @name,
        "tenant" => @tenant,
        "flavor_id" => @flavor_id,
        "key_name" => @key_name,
        "sec_group" => @sec_group,
        "auth_url" => @auth_url
      }
    end

    it 'should provision a machine' do
      wi = Ruote::Workitem.new({"fields" => @fields})
      @worker.stub(:workitem => wi.to_h)
      @worker.provision

      wi.fields['__error__'].should be nil
      wi.fields['openstack_api_key'].should eq(@api_key)
      wi.fields['openstack_username'].should eq(@username)
      wi.fields['openstack_auth_url'].should eq(@auth_url)

    end

    # can't test it with mock
    # it 'should fail when image does not exist' do
    #  wi = Ruote::Workitem.new({"fields" => @fields.merge({"auth_url" => @auth_url})})
    #  @worker.stub(:workitem => wi.to_h)
    #  @worker.provision
    #
    #  wi.fields['__error__'].should be nil
    #  wi.fields['rackspace_api_key'].should eq(@api_key)
    #  wi.fields['rackspace_username'].should eq(@username)
    #  wi.fields['rackspace_auth_url'].should eq(@auth_url)
    #end
  end


end

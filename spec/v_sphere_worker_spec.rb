# Copyright 2012© MaestroDev.  All rights reserved.

USE_STOMP=false
require 'spec_helper'

describe MaestroDev::VSphereWorker do

  before(:all) do
    Fog.mock!
    @worker = MaestroDev::VSphereWorker.new
  end

  describe 'provision' do

    fields = {
      "params" => {"command" => "provision"},
      "host" => "localhost",
      "datacenter" => "Solutions",
      "username" => "root",
      "password" => "password",
      "template_name" => "centos56gm",
      "vm_name" => "new vm",
      "ssh_commands" => ["hostname"]
    }

    it 'should provision a machine' do
      wi = Ruote::Workitem.new({"fields" => fields})
      @worker.stubs(:workitem => wi.to_h)
      @worker.provision

      wi.fields['ids'].should eq(["vm-698"])
      wi.fields['__error__'].should eq(nil)
    end

    it 'should fail when template does not exist' do
      wi = Ruote::Workitem.new({"fields" => fields.merge({"template_name" => "doesnotexist"})})

      @worker.stubs(:workitem => wi.to_h)
      @worker.provision
      wi.fields['__error__'].should eq("VM template '/Datacenters/Solutions/doesnotexist' not found")
    end
  end

  describe 'deprovision' do
    fields = {
      "params" => {"command" => "deprovision"},
      "host" => "localhost",
      "username" => "root",
      "password" => "password",
      "ids" => ["vm-698", "vm-640"],
    }

    it 'should deprovision a machine' do
      wi = Ruote::Workitem.new({"fields" => fields})

      @worker.stubs(:workitem => wi.to_h)
      @worker.deprovision
      wi.fields['__error__'].should eq(nil)
    end
  end
end

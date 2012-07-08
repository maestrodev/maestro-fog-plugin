# Copyright 2012© MaestroDev.  All rights reserved.

USE_STOMP=false
require 'spec_helper'

describe MaestroDev::VSphereWorker do

  before(:all) do
    Fog.mock!
    @worker = MaestroDev::VSphereWorker.new
  end

  describe 'provision' do
    it 'should provision a machine' do
      wi = Ruote::Workitem.new({"fields" => {"params" => {"command" => "provision"},
        "host" => "localhost",
        "datacenter" => "Solutions",
        "username" => "root",
        "password" => "password",
        "template_name" => "centos56gm",
        "vm_name" => "new vm",
        "ssh_commands" => ["hostname"]
      }})

      @worker.stubs(:workitem => wi.to_h)
      @worker.provision
      wi.fields['__error__'].should eq(nil)
    end
  end

  describe 'deprovision' do
    it 'should deprovision a machine' do
      wi = Ruote::Workitem.new({"fields" => {"params" => {"command" => "deprovision"},
        "host" => "localhost",
        "username" => "root",
        "password" => "password",
        "instance_uuids" => ["1111"],
      }})

      @worker.stubs(:workitem => wi.to_h)
      @worker.deprovision
      wi.fields['__error__'].should eq(nil)
    end
  end
end

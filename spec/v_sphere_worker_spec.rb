# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'

describe MaestroDev::VSphereWorker do

  def connect
    Fog::Compute.new(
      :provider => "vsphere",
      :vsphere_username => @username,
      :vsphere_password => @password,
      :vsphere_server => @host)
  end

  before(:all) do
    Fog.mock!
    @worker = MaestroDev::VSphereWorker.new

    # mock
    @host = "localhost"
    @datacenter = "Solutions"
    @username = 'root'
    @password = 'password'
    @template_name = 'centos56gm'
    @vm_name = 'new vm'

    # test
    # @host = "172.16.184.129"
    # @datacenter = 'ha-datacenter'
    # @username = 'root'
    # @password = 'vagrant'
    # @template_name = 'test template'
    # @vm_name = 'test 2'
  end

  describe 'provision' do

    before(:all) do
      @fields = {
        "params" => {"command" => "provision"},
        "host" => @host,
        "datacenter" => @datacenter,
        "username" => @username,
        "password" => @password,
        "template_name" => @template_name,
        "vm_name" => "xxx",
        "ssh_commands" => ["hostname"]
      }
    end

    it 'should provision a machine' do
      wi = Ruote::Workitem.new({"fields" => @fields})
      @worker.stub(:workitem => wi.to_h)
      @worker.provision

      wi.fields['__error__'].should eq(nil)
      wi.fields['vsphere_host'].should eq(@host)
      wi.fields['vsphere_username'].should eq(@username)
      wi.fields['vsphere_password'].should eq(@password)
      wi.fields['vsphere_ids'].should eq(["vm-698"])
    end

    it 'should fail when template does not exist' do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"template_name" => "doesnotexist"})})

      @worker.stub(:workitem => wi.to_h)
      @worker.provision
      wi.fields['__error__'].should eq("VM template '/Datacenters/Solutions/doesnotexist' not found")
    end
  end

  describe 'deprovision' do

    before(:all) do
      @fields = {
        "params" => {"command" => "deprovision"},
        "vsphere_host" => @host,
        "vsphere_username" => @username,
        "vsphere_password" => @password,
        "vsphere_ids" => ["vm-698", "vm-640"],
      }
    end

    it 'should deprovision a machine' do
      wi = Ruote::Workitem.new({"fields" => @fields})

      @worker.stub(:workitem => wi.to_h)
      @worker.deprovision
      wi.fields['__error__'].should eq(nil)
    end

    it 'should stop machine before deprovisioning' do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"vsphere_ids" => ["vm-669"]})})

      connection = connect()
      s = connection.servers.get("vm-669")

      servers = double("servers")
      connection.stub(:servers => servers)
      @worker.stub(:connect => connection)
      @worker.stub(:workitem => wi.to_h)

      servers.should_receive(:get).with("vm-669").and_return(s)
      s.ready?.should == true
      s.should_receive(:stop).once

      @worker.deprovision
      wi.fields['__error__'].should eq(nil)
    end
  end
end

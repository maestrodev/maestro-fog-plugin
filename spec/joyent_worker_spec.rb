# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'joyent_worker'

describe MaestroDev::JoyentWorker, :provider => "joyent", :skip => true do

  def connect
    Fog::Compute.new(
      :provider => "joyent",
      :joyent_username => @username,
      :joyent_password => @password,
      :joyent_url => @url)
  end

  before(:all) do
    @worker = MaestroDev::JoyentWorker.new
    @username = "maestrodev"
    @password = "xxx"
    @url = "https://api-mad.instantservers.es"
    @package = "Small 2GB"
    @dataset = "centos-6"
  end

  describe 'provision' do

    before(:all) do
      Fog.mock!
      @fields = {
        "params" => {"command" => "provision"},
        "username" => @username,
        "password" => @password,
        "url" => @url
      }
    end

    it 'should provision a machine' do
      wi = Ruote::Workitem.new({"fields" => @fields})
      @worker.stub(:workitem => wi.to_h)
      @worker.provision

      wi.fields['__error__'].should be nil
      wi.fields['joyent_username'].should eq(@username)
      wi.fields['joyent_password'].should eq(@password)
      wi.fields['joyent_url'].should eq(@url)
      wi.fields['joyent_ids'].should_not be_empty
      wi.fields['joyent_ids'].size.should be 1
    end

    it 'should fail when image does not exist' do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"dataset" => "qqqqqq"})})
    
      @worker.stub(:workitem => wi.to_h)
      @worker.provision
      wi.fields['__error__'].should_not be_empty
    end

  end

  describe 'deprovision' do

    before(:all) do
      Fog.mock!
      @fields = {
        "params" => {"command" => "deprovision"},
        "joyent_username" => @username,
        "joyent_password" => @password
      }
    end

    it 'should deprovision a machine' do
      connection = connect

      # create 2 servers
      stubs = {}
      (1..2).each do |i|

        s = connection.servers.create(:package => @package,
                                      :dataset => @dataset,
                                      :name => @name)
        s.wait_for { ready? }
        stubs[s.id]=s
      end

      wi = Ruote::Workitem.new({"fields" => @fields.merge({"joyent_ids" => stubs.keys})})
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
      wi.fields['__error__'].should be_nil
    end

  end
end

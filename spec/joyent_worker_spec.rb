# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'joyent_worker'

describe MaestroDev::FogPlugin::JoyentWorker, :provider => "joyent", :disabled => true do

  def connect
    Fog::Compute.new(
      :provider => "joyent",
      :joyent_username => @username,
      :joyent_password => @password,
      :joyent_url => @url)
  end

  before(:each) do
    subject.stub(:send_workitem_message)
    @username = "maestrodev"
    @password = "xxx"
    @url = "https://api-mad.instantservers.es"
    @package = "Small 2GB"
    @dataset = "centos-6"
  end

  describe 'provision' do

    before(:each) do
      @fields = {
        "params" => {"command" => "provision"},
        "username" => @username,
        "password" => @password,
        "url" => @url
      }
    end

    it 'should provision a machine' do
      subject.stub(:workitem => {"fields" => @fields})
      subject.provision

      subject.error.should be_nil
      subject.get_field('joyent_username').should eq(@username)
      subject.get_field('joyent_password').should eq(@password)
      subject.get_field('joyent_url').should eq(@url)
      subject.get_field('joyent_ids').should_not be_empty
      subject.get_field('joyent_ids').size.should be 1
    end

    it 'should fail when image does not exist' do
      subject.stub(:workitem => {"fields" => @fields.merge({"dataset" => "qqqqqq"})})
      subject.provision
      subject.error.should_not be_empty
    end

  end

  describe 'deprovision' do

    before(:each) do
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

      subject.stub(:workitem => {"fields" => @fields.merge({"joyent_ids" => stubs.keys})})
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

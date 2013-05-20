# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'aws_worker'

describe MaestroDev::AwsWorker, :provider => "aws" do

  def connect
    Fog::Compute.new(
      :provider => "aws",
      :aws_access_key_id => @access_key_id,
      :aws_secret_access_key => @secret_access_key)
  end

  before(:each) do
    @worker = MaestroDev::AwsWorker.new
    @worker.stub(:send_workitem_message)
    @access_key_id = "xxx"
    @secret_access_key = "yyy"
    @image_id = "ami-xxxxxx"
    @flavor_id = "y"
  end

  describe 'provision' do

    before(:each) do
      @connection = connect
      @fields = {
        "params" => {"command" => "provision"},
        "access_key_id" => @access_key_id,
        "secret_access_key" => @secret_access_key,
        "image_id" => @image_id,
        "flavor_id" => @flavor_id
      }
    end

    it 'should provision a machine' do
      wi = Ruote::Workitem.new({"fields" => @fields})
      @worker.stub(:workitem => wi.to_h)
      @worker.provision

      wi.fields['__error__'].should be nil
      wi.fields['aws_access_key_id'].should eq(@access_key_id)
      wi.fields['aws_secret_access_key'].should eq(@secret_access_key)
      wi.fields['aws_ids'].should_not be_empty
      wi.fields['aws_ids'].size.should be 1
      wi.fields['__context_outputs__']['servers'].length.should == 1
    end

    it 'should fail when image does not exist' do
      wi = Ruote::Workitem.new({"fields" => @fields.merge({"image_id" => "ami-qqqqqq"})})
      @worker.stub(:connect => @connection)
      servers = double("servers")
      @connection.stub(:servers => servers)
      servers.should_receive(:create).once.and_raise(Fog::Compute::AWS::NotFound.new("The AMI ID 'ami-qqqqqq' does not exist"))
      @worker.stub(:workitem => wi.to_h)
      @worker.provision
      wi.fields['__error__'].should eq("Image id 'ami-qqqqqq', flavor 'y' not found")
    end

  end

  describe 'deprovision' do

    before(:each) do
      @connection = connect
      @worker.stub(:connect => @connection)
      @fields = {
        "params" => {"command" => "deprovision"},
        "aws_access_key_id" => @access_key_id,
        "aws_secret_access_key" => @secret_access_key
      }
    end

    it 'should deprovision a machine' do
      # create 2 servers
      stubs = {}
      (1..2).each do |i|

        s = @connection.servers.create(:image_id => @image_id,
                                       :flavor_id => @flavor_id)
        s.wait_for { ready? }
        stubs[s.id]=s
      end
      stubs.size.should == 2

      wi = Ruote::Workitem.new({"fields" => @fields.merge({"aws_ids" => stubs.keys})})
      @worker.stub(:workitem => wi.to_h)
      servers = double("servers")
      @connection.stub(:servers => servers)

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

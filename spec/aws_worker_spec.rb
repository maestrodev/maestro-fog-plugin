# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'aws_worker'

describe MaestroDev::FogPlugin::AwsWorker, :provider => "aws" do

  let(:connection) {
    Fog::Compute.new(
      :provider => "aws",
      :aws_access_key_id => @access_key_id,
      :aws_secret_access_key => @secret_access_key)
  }

  before(:each) do
    subject.stub(:send_workitem_message)
    @access_key_id = "xxx"
    @secret_access_key = "yyy"
    @image_id = "ami-xxxxxx"
    @flavor_id = "y"
  end

  describe 'provision' do

    let(:fields) {{
        "params" => {"command" => "provision"},
        "access_key_id" => @access_key_id,
        "secret_access_key" => @secret_access_key,
        "image_id" => @image_id,
        "flavor_id" => @flavor_id
    }}

    it 'should provision a machine' do
      subject.stub(:workitem => {"fields" => fields})
      subject.provision

      subject.error.should be_nil
      subject.get_field('aws_access_key_id').should eq(@access_key_id)
      subject.get_field('aws_secret_access_key').should eq(@secret_access_key)
      subject.get_field('aws_ids').should_not be_empty
      subject.get_field('aws_ids').size.should be 1
      subject.get_field('__context_outputs__')['servers'].length.should == 1
    end

    it 'should fail when image does not exist' do
      subject.stub(:connect => connection)
      servers = double("servers")
      connection.stub(:servers => servers)
      servers.should_receive(:create).once.and_raise(Fog::Compute::AWS::NotFound.new("The AMI ID 'ami-qqqqqq' does not exist"))
      subject.stub(:workitem => {"fields" => fields.merge({"image_id" => "ami-qqqqqq"})})
      subject.provision
      subject.error.should eq("Image id 'ami-qqqqqq', flavor 'y' not found")
    end

  end

  describe 'deprovision' do

    let(:fields) {{
        "params" => {"command" => "deprovision"},
        "aws_access_key_id" => @access_key_id,
        "aws_secret_access_key" => @secret_access_key
    }}

    it 'should deprovision a machine' do
      subject.stub(:connect => connection)
      # create 2 servers
      stubs = {}
      (1..2).each do |i|

        s = connection.servers.create(:image_id => @image_id,
                                       :flavor_id => @flavor_id)
        s.wait_for { ready? }
        stubs[s.identity]=s
      end
      stubs.size.should == 2

      subject.stub(:workitem => {"fields" => fields.merge({"aws_ids" => stubs.keys})})
      servers = double("servers")
      connection.stub(:servers => servers)

      stubs.values.each do |s|
        servers.should_receive(:get).once.with(s.identity).and_return(s)
        s.ready?.should == true
        s.should_receive(:destroy).once
        s.should_not_receive(:stop)
      end

      subject.deprovision
      subject.error.should be_nil
    end

  end
end

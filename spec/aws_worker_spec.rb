# Copyright 2012© MaestroDev.  All rights reserved.

require 'spec_helper'
require 'aws_worker'

describe MaestroDev::Plugin::AwsWorker, :provider => "aws" do

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

  after(:each) do
    connection.servers.dup.each { |s| s.destroy } if connection.servers.kind_of?(Array)
    connection.addresses.dup.each { |a| a.destroy }
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
      subject.get_field('aws_ids').size.should == 1
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

  describe 'associate_address' do

    let(:fields) {{
        "access_key_id" => @access_key_id,
        "secret_access_key" => @secret_access_key
    }}

    it 'should associate an ip address with an instance id' do
      workitem = {'fields' => fields}

      # create a server
      server = connection.servers.create(:image_id => @image_id,
                                       :flavor_id => @flavor_id)
      server.wait_for { ready? }

      # create an address
      ip_addr = connection.allocate_address.data[:body]['publicIp']

      fields['instance_id'] = server.id
      fields['ip_address'] = ip_addr

      subject.perform(:associate_address, workitem)

      server.reload
      address = connection.describe_addresses('public-ip' => ip_addr).data[:body]['addressesSet'][0]

      address['instanceId'].should == server.id
      server.public_ip_address.should == ip_addr

      server.destroy
    end

    it 'should associate an ip address with an instance id from previous task' do
      workitem = {'fields' => fields}

      workitem['fields']['image_id'] = @image_id,
      workitem['fields']['flavor_id'] = @flavor_id

      subject.perform(:provision, workitem)

      server = connection.servers.get(workitem['fields']['aws_ids'][0])

      # create an address
      ip_addr = connection.allocate_address.data[:body]['publicIp']

#      fields['instance_id'] = server.id
      fields['ip_address'] = ip_addr

      subject.perform(:associate_address, workitem)

      server.reload
      address = connection.describe_addresses('public-ip' => ip_addr).data[:body]['addressesSet'][0]

      address['instanceId'].should == server.id
      server.public_ip_address.should == ip_addr

      server.destroy
    end

    it 'should fail to associate an invalid ip address with an instance id' do
      workitem = {'fields' => fields}

      # create a server
      server = connection.servers.create(:image_id => @image_id,
                                         :flavor_id => @flavor_id)
      server.wait_for { ready? }

      # pick a random ip address
      ip_addr = '1.2.3.4'

      fields['instance_id'] = server.id
      fields['ip_address'] = ip_addr

      subject.perform(:associate_address, workitem)

      workitem['fields']['__error__'].should start_with('Unable to locate elastic ip address')

      server.destroy
    end

    it 'should fail to associate an ip address with an instance id if it is already assigned and not overridden' do
      workitem = {'fields' => fields}

      # create a server
      existing_server = connection.servers.create(:image_id => @image_id,
                                         :flavor_id => @flavor_id)
      existing_server.wait_for { ready? }

      server = connection.servers.create(:image_id => @image_id,
                                         :flavor_id => @flavor_id)
      server.wait_for { ready? }

      # create an address
      ip_addr = connection.allocate_address.data[:body]['publicIp']

      fields['instance_id'] = existing_server.id
      fields['ip_address'] = ip_addr

      subject.perform(:associate_address, workitem)

      existing_server.reload
      address = connection.describe_addresses('public-ip' => ip_addr).data[:body]['addressesSet'][0]

      address['instanceId'].should == existing_server.id
      existing_server.public_ip_address.should == ip_addr

      fields['instance_id'] = server.id
      subject.perform(:associate_address, workitem)

      workitem['fields']['__error__'].should start_with("Elastic ip address #{ip_addr} is already associated with server id #{existing_server.id}")

      server.destroy
      existing_server.destroy
    end

    it 'should associate an ip address with an instance id if it is already assigned and overridde is allowed' do
      workitem = {'fields' => fields}

      # create a server
      existing_server = connection.servers.create(:image_id => @image_id,
                                         :flavor_id => @flavor_id)
      existing_server.wait_for { ready? }
      init_ip_addr = existing_server.public_ip_address
      server = connection.servers.create(:image_id => @image_id,
                                         :flavor_id => @flavor_id)
      server.wait_for { ready? }

      # create an address
      ip_addr = connection.allocate_address.data[:body]['publicIp']

      fields['instance_id'] = existing_server.id
      fields['ip_address'] = ip_addr
      fields['reassign_if_assigned'] = true

      subject.perform(:associate_address, workitem)

      existing_server.reload
      address = connection.describe_addresses('public-ip' => ip_addr).data[:body]['addressesSet'][0]

      address['instanceId'].should == existing_server.id
      existing_server.public_ip_address.should == ip_addr

      fields['instance_id'] = server.id
      subject.perform(:associate_address, workitem)

      existing_server.reload
      server.reload
      address = connection.describe_addresses('public-ip' => ip_addr).data[:body]['addressesSet'][0]

      address['instanceId'].should == server.id
      existing_server.public_ip_address.should == init_ip_addr
      server.public_ip_address.should == ip_addr

      server.destroy
      existing_server.destroy
    end
  end

  describe 'disassociate_address' do
    #
    # Important - the worker code calls two different versions of 'disassociate_address' on fog
    # one for testing, and one for production.  Its not nice, but:
    # 1. the Mock version of the method accepts wrong # of params, and even if we fixed that:
    # 2. the Mock association code doesn't set association_id for any ip's (just returns random id)
    # So the method won't work anyway
    #

    let(:fields) {{
        "access_key_id" => @access_key_id,
        "secret_access_key" => @secret_access_key,
        "ip_address" => '1.2.3.4'
    }}

    it "should not bother to disassociate an ip address that isn't assigned" do
      workitem = {'fields' => fields}

      # create an address
      ip_addr = connection.allocate_address.data[:body]['publicIp']

      fields['ip_address'] = ip_addr

      subject.perform(:disassociate_address, workitem)

      workitem['__output__'].should include("IP #{ip_addr} not assigned to any instances")
      workitem['fields']['__error__'].should be_nil
    end

    it "should disassociate an ip address that is assigned" do
      workitem = {'fields' => fields}

      # create a server
      server = connection.servers.create(:image_id => @image_id,
                                       :flavor_id => @flavor_id)
      server.wait_for { ready? }
      orig_ip_addr = server.public_ip_address

      # create an address
      ip_addr = connection.allocate_address.data[:body]['publicIp']

      fields['instance_id'] = server.id
      fields['ip_address'] = ip_addr

      subject.perform(:associate_address, workitem)

      server.reload
      address = connection.describe_addresses('public-ip' => ip_addr).data[:body]['addressesSet'][0]

      address['instanceId'].should == server.id
      server.public_ip_address.should == ip_addr

      fields.delete('instance_id')
      fields['ip_address'] = ip_addr

      subject.perform(:disassociate_address, workitem)

      server.reload
      address = connection.describe_addresses('public-ip' => ip_addr).data[:body]['addressesSet'][0]

      address['instanceId'].should be_nil
      server.public_ip_address.should == orig_ip_addr

      workitem['__output__'].should include("Disassociating elastic ip #{ip_addr} from instance #{server.id}")
      workitem['fields']['__error__'].should be_nil
    end

    it "should disassociate an ip address that is assigned to the instance it is expected to be" do
      workitem = {'fields' => fields}

      # create a server
      server = connection.servers.create(:image_id => @image_id,
                                       :flavor_id => @flavor_id)
      server.wait_for { ready? }
      orig_ip_addr = server.public_ip_address

      # create an address
      ip_addr = connection.allocate_address.data[:body]['publicIp']

      fields['instance_id'] = server.id
      fields['ip_address'] = ip_addr

      subject.perform(:associate_address, workitem)

      server.reload
      address = connection.describe_addresses('public-ip' => ip_addr).data[:body]['addressesSet'][0]

      address['instanceId'].should == server.id
      server.public_ip_address.should == ip_addr

      fields['ip_address'] = ip_addr

      subject.perform(:disassociate_address, workitem)

      server.reload
      address = connection.describe_addresses('public-ip' => ip_addr).data[:body]['addressesSet'][0]

      address['instanceId'].should be_nil
      server.public_ip_address.should == orig_ip_addr

      workitem['__output__'].should include("Disassociating elastic ip #{ip_addr} from instance #{server.id}")
      workitem['fields']['__error__'].should be_nil
    end

    it "should fail to disassociate an ip address that is assigned to a different instance id" do
      workitem = {'fields' => fields}

      # create a server
      server = connection.servers.create(:image_id => @image_id,
                                       :flavor_id => @flavor_id)
      server.wait_for { ready? }
      orig_ip_addr = server.public_ip_address

      # create an address
      ip_addr = connection.allocate_address.data[:body]['publicIp']

      fields['instance_id'] = server.id
      fields['ip_address'] = ip_addr

      subject.perform(:associate_address, workitem)

      server.reload
      address = connection.describe_addresses('public-ip' => ip_addr).data[:body]['addressesSet'][0]

      address['instanceId'].should == server.id
      server.public_ip_address.should == ip_addr

      fields['instance_id'] = 'other_server'
      fields['ip_address'] = ip_addr

      subject.perform(:disassociate_address, workitem)

      server.reload
      address = connection.describe_addresses('public-ip' => ip_addr).data[:body]['addressesSet'][0]

      address['instanceId'].should == server.id
      server.public_ip_address.should == ip_addr

      workitem['fields']['__error__'].should == "Elastic ip address #{ip_addr} is not associated with instance other_server.  Not updating.  (Associated with instance #{server.id})"
    end
  end
end

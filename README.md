# maestro-fog-plugin
[Maestro](http://www.maestrodev.com) plugin providing tasks to provision instances with [fog](http://fog.io/). This plugin is a Ruby-based deployable that gets delivered as a ZIP file.

Currently supporting

 * [Rackspace](#rackspace)
 * [Openstack](#openstack)
 * [Joyent](#joyent)
 * [InstantServers](#InstantServers)
 * [VMWare vSphere](#vsphere)

After the VMs/instances are started, the plugin can execute **SSH** commands on them. For that to happen sometimes public/private SSH keys need to be configured in the VM or in the plugin fields if possible.

# Requirements

Requires Maestro 4.10+ and Maestro Agent 1.11+

# Common parameters
* **number_of_vms**: number of vms/instances to start (defaults to 1)
* name: if set it will assign a name to the VM when possible, otherwise the name will be random. If number_of_vms > 1, then the a random id will be appended (ie. vm_qwert, vm_asdfg, vm_zxcvb,...)
* ssh_commands: commands to execute on each vm after started, they are executed as one script, so task will only fail if the last one does, or use [bash set -e](http://linux.die.net/man/1/bash) appropiately
* ssh_user: username to use when connecting to the vm using ssh (defaults to root)
* ssh_password: password to use for ssh connections if not using the ssh key (keys take precedence)
* private_key: SSH private key content (if not using private_key_path)
* private_key_path: SSH private key path (if not using private_key). The file must exist in the agents and path must be accessible from the agents that run the task.

# Outputs
All provision tasks will set some fields that can be reused in later tasks using Ruby syntax.

* **fields[:cloud_ips]**: array with the ips of the servers started in all providers in current composition
* **fields[:cloud_ips]**: array with the ips of the servers started in all providers in current composition
* **fields[:cloud_names]**: array with the names of the servers started in all providers in current composition
* **fields[:provider_name_ips]**: array with the ips of the servers started (ie. fields[:rackspace_ips])
* **fields[:provider_name_ids]**: array with the ids of the servers started (ie. fields[:rackspace_ids])
* **fields[:provider_name_names]**: array with the name of the servers started (ie. fields[:rackspace_ids])

For instance you can add a confirmation task that will display the ips of the vms using ruby syntax

	Servers started at #{fields[:rackspace_ips].join(', ')}
	
Or to display urls to those vms

	Servers available at #{fields[:rackspace_ips].map { |ip| 'http://' + ip + ':8080'}.join(', ')}

You can ssh to the first vm started using the ssh execute task and this hostname

	#{fields[:cloud_ips].first}


# Rackspace
* **username**: Rackspace account username
* **api_key**: Rackspace account API key
* **version**: API version to use: **v1** or **v2** for Open Cloud Servers
* **endpoint**: endpoint used for Rackspace v2, choosing the region to use (ie. *https://dfw.servers.api.rackspacecloud.com/v2*)
* **auth_url**: authentication endpoint, default to https://identity.api.rackspacecloud.com/v2.0 for US accounts, https://lon.identity.api.rackspacecloud.com/v2.0 for UK ones. Refer to http://docs.rackspace.com/auth/api/v2.0/auth-client-devguide/content/Endpoints-d1e180.html (ie. *https://identity.api.rackspacecloud.com/v2.0*)
* **image_id**: id of the image to use (ie. *c195ef3b-9195-4474-b6f7-16e5bd86acd0* for CentOS 6.3 in v2)
* **flavor_id**: id of the server flavor to use (RAM, CPU,…)
* **public_key**: public key content to copy to the server as authorized key
* **public_key_path**: path to public key to copy to the server as authorized key

You can find the image_id and flavor_id by adding a server from the Rackspace UI or using the API for [images](http://docs.rackspace.com/servers/api/v1.0/cs-devguide/content/List_Images-d1e4070.html) and [flavors](http://docs.rackspace.com/servers/api/v1.0/cs-devguide/content/List_Flavors-d1e3842.html).

### Some image ids for v1

<table>
<tr><td>100</td><td>Arch 2011.10</td></tr><tr><td>114</td><td>CentOS 5.6</td></tr><tr><td>121</td><td>CentOS 5.8</td></tr><tr><td>118</td><td>CentOS 6.0</td></tr><tr><td>122</td><td>CentOS 6.2</td></tr><tr><td>103</td><td>Debian 5 (Lenny)</td></tr><tr><td>104</td><td>Debian 6 (Squeeze)</td></tr><tr><td>116</td><td>Fedora 15</td></tr><tr><td>120</td><td>Fedora 16</td></tr><tr><td>126</td><td>Fedora 17</td></tr><tr><td>108</td><td>Gentoo 11.0</td></tr><tr><td>110</td><td>Red Hat Enterprise Linux 5.5</td></tr><tr><td>111</td><td>Red Hat Enterprise Linux 6</td></tr><tr><td>112</td><td>Ubuntu 10.04 LTS</td></tr><tr><td>115</td><td>Ubuntu 11.04</td></tr><tr><td>119</td><td>Ubuntu 11.10</td></tr><tr><td>125</td><td>Ubuntu 12.04 LTS</td></tr><tr><td>85</td><td>Windows Server 2008 R2 (64-bit)</td></tr><tr><td>86</td><td>Windows Server 2008 R2 (64-bit) + SQL Server 2008 R2 Standard</td></tr><tr><td>89</td><td>Windows Server 2008 R2 (64-bit) + SQL Server 2008 R2 Web</td></tr><tr><td>91</td><td>Windows Server 2008 R2 (64-bit) + SQL Server 2012 Standard</td></tr><tr><td>92</td><td>Windows Server 2008 R2 (64-bit) + SQL Server 2012 Web</td></tr><tr><td>31</td><td>Windows Server 2008 SP2 (32-bit)</td></tr><tr><td>56</td><td>Windows Server 2008 SP2 (32-bit) + SQL Server 2008 R2 Standard</td></tr><tr><td>24</td><td>Windows Server 2008 SP2 (64-bit)</td></tr><tr><td>57</td><td>Windows Server 2008 SP2 (64-bit) + SQL Server 2008 R2 Standard</td></tr><tr><td>109</td><td>openSUSE 12</td></tr>
</table>


### Some flavor ids for v1

<table>
<tr><td>1</td><td>256 server</td></tr>
<tr><td>2</td><td>512 server</td></tr>
<tr><td>3</td><td>1GB server</td></tr>
<tr><td>4</td><td>2GB server</td></tr>
<tr><td>5</td><td>4GB server</td></tr>
<tr><td>6</td><td>8GB server</td></tr>
<tr><td>7</td><td>15.5GB server</td></tr>
<tr><td>8</td><td>30GB server</td></tr>
</table>

### Some image ids for v2

<table>
<tr><td>e0ed4adb-3a00-433e-a0ac-a51f1bc1ea3d</td><td>CentOS 6.4</td></tr>
<tr><td>992ba82c-083b-4eed-9c26-c54473686466</td><td>Windows Server 2012 + SharePoint Foundation 2013 with SQL Server 2012 Standard</td></tr>
<tr><td>8a3a9f96-b997-46fd-b7a8-a9e740796ffd</td><td>Ubuntu 12.10 (Quantal Quetzal)</td></tr>
<tr><td>a3a2c42f-575f-4381-9c6d-fcd3b7d07d17</td><td>CentOS 6.0</td></tr>
<tr><td>d6dd6c70-a122-4391-91a8-decb1a356549</td><td>Red Hat Enterprise Linux 6.1</td></tr>
<tr><td>5cebb13a-f783-4f8c-8058-c4182c724ccd</td><td>Ubuntu 12.04 LTS (Precise Pangolin)</td></tr>
<tr><td>7957e53d-b3b9-41fe-8e0d-5252bf20a5bf</td><td>Windows Server 2008 R2 SP1 (with updates)</td></tr>
<tr><td>b762ee1d-11b5-4ae7-aa68-dcc1b6f6e24a</td><td>Windows Server 2012 (with updates) + SQL Server 2012 Web</td></tr>
<tr><td>f86eae6d-09ea-42e6-a5b2-422649edcfa1</td><td>Windows Server 2012 (with updates) + SQL Server 2012 Standard</td></tr>
<tr><td>057d2670-68bc-4e28-b7b1-b9bc72245683</td><td>Windows Server 2012 + SQL Server 2012 Web</td></tr>
<tr><td>d226f189-f83f-4569-95b8-622133d71f02</td><td>Windows Server 2012 + SQL Server 2012 Standard</td></tr>
<tr><td>2748ee06-ff35-4518-9759-4acb57bad4c3</td><td>Windows Server 2012 (with updates)</td></tr>
<tr><td>acf05b3c-5403-4cf0-900c-9b12b0db0644</td><td>CentOS 5.8</td></tr>
<tr><td>c94f5e59-0760-467a-ae70-9a37cfa6b94e</td><td>Arch 2012.08</td></tr>
<tr><td>110d5bd8-a0dc-4cf5-8e75-149a58c17bbf</td><td>Gentoo 12.3</td></tr>
<tr><td>9eb71a23-2c7e-479c-a6b1-b38aa64f172e</td><td>Windows Server 2008 R2 SP1 + SharePoint Foundation 2010 SP1 & SQL Server 2008 R2 SP1 Std</td></tr>
<tr><td>7f7183b0-856c-4894-afae-9e52839ce197</td><td>Windows Server 2008 R2 SP1 + SharePoint Foundation 2010 SP1 & SQL Server 2008 R2 SP1 Express</td></tr>
<tr><td>ae49b64d-9d68-4b36-98ed-b1ce84944680</td><td>Windows Server 2012</td></tr>
<tr><td>d531a2dd-7ae9-4407-bb5a-e5ea03303d98</td><td>Ubuntu 10.04 LTS (Lucid Lynx)</td></tr>
<tr><td>f7d06722-2b30-4c02-b74d-da5a7337f357</td><td>Windows Server 2008 R2 SP1 + SQL Server 2012 Standard</td></tr>
<tr><td>e7a11eed-d348-44da-8210-f136d4256e81</td><td>Windows Server 2008 R2 SP1 + SQL Server 2012 Web</td></tr>
<tr><td>e4589dc6-b972-482f-91ef-67feb891b559</td><td>Windows Server 2008 R2 SP1 (with updates) + SQL Server 2012 Standard</td></tr>
<tr><td>d6153e86-f4e0-4053-a711-d35632e512cd</td><td>Windows Server 2008 R2 SP1 + SQL Server 2008 R2 Web</td></tr>
<tr><td>80599479-b5a2-49f2-bb46-2bc75a8be98b</td><td>Windows Server 2008 R2 SP1 (with updates) + SQL Server 2008 R2 SP1 Web</td></tr>
<tr><td>6f8ab5a1-42ff-433b-be40-e17374f2fff4</td><td>Windows Server 2008 R2 SP1 (with updates) + SQL Server 2012 Web</td></tr>
<tr><td>535d5453-79dd-4635-bbd6-d87b1f1cd717</td><td>Windows Server 2008 R2 SP1 (with updates) + SQL Server 2008 R2 SP1 Standard</td></tr>
<tr><td>2a4a02aa-523a-4649-9802-3a09de8e5f1b</td><td>Windows Server 2008 R2 SP1 + SQL Server 2008 R2 Standard</td></tr>
<tr><td>b9ea8426-8f43-4224-a182-7cdb2bb897c8</td><td>Windows Server 2008 R2 SP1</td></tr>
<tr><td>c79fecf7-2c37-4c51-a240-e9fa913c90a3</td><td>FreeBSD 9</td></tr>
<tr><td>c195ef3b-9195-4474-b6f7-16e5bd86acd0</td><td>CentOS 6.3</td></tr>
<tr><td>d42f821e-c2d1-4796-9f07-af5ed7912d0e</td><td>Fedora 17 (Beefy Miracle)</td></tr>
<tr><td>0cab6212-f231-4abd-9c70-608d0d0e04ba</td><td>CentOS 6.2</td></tr>
<tr><td>644be485-411d-4bac-aba5-5f60641d92b5</td><td>Red Hat Enterprise Linux 5.5</td></tr>
<tr><td>8bf22129-8483-462b-a020-1754ec822770</td><td>Ubuntu 11.04 (Natty Narwhal)</td></tr>
<tr><td>096c55e5-39f3-48cf-a413-68d9377a3ab6</td><td>openSUSE 12.1</td></tr>
<tr><td>a10eacf7-ac15-4225-b533-5744f1fe47c1</td><td>Debian 6 (Squeeze)</td></tr>
<tr><td>bca91446-e60e-42e7-9e39-0582e7e20fb9</td><td>Fedora 16 (Verne)</td></tr>
<tr><td>03318d19-b6e6-4092-9b5c-4758ee0ada60</td><td>CentOS 5.6</td></tr>
<tr><td>3afe97b2-26dc-49c5-a2cc-a2fc8d80c001</td><td>Ubuntu 11.10 (Oneiric Oncelot)</td></tr>
</table>

### Some flavor ids for v2

<table>
<tr><td>2</td><td>512MB Standard Instance</td></tr>
<tr><td>3</td><td>1GB Standard Instance</td></tr>
<tr><td>4</td><td>2GB Standard Instance</td></tr>
<tr><td>5</td><td>4GB Standard Instance</td></tr>
<tr><td>6</td><td>8GB Standard Instance</td></tr>
<tr><td>7</td><td>15GB Standard Instance</td></tr>
<tr><td>8</td><td>30GB Standard Instance</td></tr>
</table>


# Openstack
* **auth_url**: the URL where the autentication service can be reached (ie. *http://hostname:35357/v2.0/tokens*)
* **tenant**: the OpenStack tenant (aka project)
* **username**: username
* **api_key**: API key
* **region**: region identifier, may be required for some providers
* **image_id**: id of the image to use
* **flavor_id**: id of the server flavor to use (RAM, CPU,…)
* **key_name**: the name of the ssh public key to copy to the server
* **public_key**: public key content to copy to the server as authorized key
* **public_key_path**: path to public key to copy to the server as authorized key
* **security_group**: the name of the security group to add this VM to

# Google Compute Engine

To get your authorization key, visit the [Google API Console](https://code.google.com/apis/console). Once there, go to "API Access". Click "Create another client ID" and select "service account". Download the private key to be used in Maestro and take note of the Service account email address.

* **project**: Project id
* **client_email**: Service account email address
* **key_location**: Path in the agent filesystem where the pk12 private key is saved


# Joyent

* **username**: Joyent username
* **password**: Joyent password
* **url**: API endpoint (ie. *https://us-west-1.api.joyentcloud.com*)
* **package**: Describe the sizes of either a smart machine or a virtual machine
* **dataset**: The image of the software on your machine. It contains the software packages that will be available on newly provisioned machines. In the case of virtual machines, the dataset also includes the operating system

# InstantServers

[Instant Servers](http://www.instantservers.es) is a public cloud offering based on [Joyent](#Joyent) using specific endpoints, such as *https://api-mad.instantservers.es*

# vSphere
* **host**: vSphere host name
* **username**: vSphere username
* **password**: vSphere password
* **datacenter**: datacenter name
* **template_path**: path of the vm template to use, relative to the datacenter, ie. *FolderNameHere/VMNameHere*
* **destination_folder**: name of the destination folder for the created vm, relative to the Datacenter. Uses the template folder by default
* **datastore**: name of the datastore to use for the vm


# License
Apache 2.0 License

<http://www.apache.org/licenses/LICENSE-2.0.html>

# maestro-fog-plugin
[Maestro](http://www.maestrodev.com) plugin providing tasks to provision instances with [fog](http://fog.io/). This plugin is a Ruby-based deployable that gets delivered as a ZIP file.

Currently supporting

 * [Rackspace](#rackspace)
 * [VMWare vSphere](#vsphere)

After the VMs/instances are started, the plugin can execute **SSH** commands on them. For that to happen sometimes public/private SSH keys need to be configured in the VM or in the plugin fields if possible.

# Common parameters
* **number_of_vms**: number of vms/instances to start (defaults to 1)
* name: if set it will assign a name to the VM when possible, otherwise the name will be random. If number_of_vms > 1, then the number will be appended (ie. vm1, vm2, vm3,...)
* ssh_user: username to use when connecting to the vm using ssh (defaults to root)
* ssh_commands: commands to execute on each vm after started
* private_key: SSH private key content (if not using private_key_path)
* private_key_path: SSH private key path (if not using private_key). The file must exist in the agents and path must be accessible from the agents that run the task.

# Outputs
All provision tasks will set some fields that can be reused in later tasks using Ruby syntax.

* **fields[:provider_name_ips]**: array with the ips of the servers started (ie. fields[rackspace_ips])
* **fields[:provider_name_ids]**: array with the ids of the servers started(ie. fields[rackspace_ids])

For instance you can add a confirmation task that will display the ips of the vms

	Servers started at #{fields[:rackspace_ips].join(', ')}
	
Or to display urls to those vms

	Servers available at #{fields[:rackspace_ips].map { |ip| 'http://' + ip + ':8080'}.join(', ')}


# Rackspace
* **username**: Rackspace account username
* **api_key**: Rackspace account api key
* **image_id**: id of the image to use for the VMs
* **flavor_id**: id of the server flavor to use (RAM, CPU,…)
* public_key: public key to copy to the vm for connecting after started. If not set the VM will not be accessible through SSH.

You can find the image_id and flavor_id by adding a server from the Rackspace UI or using the API for [images](http://docs.rackspace.com/servers/api/v1.0/cs-devguide/content/List_Images-d1e4070.html) and [flavors](http://docs.rackspace.com/servers/api/v1.0/cs-devguide/content/List_Flavors-d1e3842.html).

### Some image ids

<table>
<tr><td>100</td><td>Arch 2011.10</td></tr><tr><td>114</td><td>CentOS 5.6</td></tr><tr><td>121</td><td>CentOS 5.8</td></tr><tr><td>118</td><td>CentOS 6.0</td></tr><tr><td>122</td><td>CentOS 6.2</td></tr><tr><td>103</td><td>Debian 5 (Lenny)</td></tr><tr><td>104</td><td>Debian 6 (Squeeze)</td></tr><tr><td>116</td><td>Fedora 15</td></tr><tr><td>120</td><td>Fedora 16</td></tr><tr><td>126</td><td>Fedora 17</td></tr><tr><td>108</td><td>Gentoo 11.0</td></tr><tr><td>110</td><td>Red Hat Enterprise Linux 5.5</td></tr><tr><td>111</td><td>Red Hat Enterprise Linux 6</td></tr><tr><td>112</td><td>Ubuntu 10.04 LTS</td></tr><tr><td>115</td><td>Ubuntu 11.04</td></tr><tr><td>119</td><td>Ubuntu 11.10</td></tr><tr><td>125</td><td>Ubuntu 12.04 LTS</td></tr><tr><td>85</td><td>Windows Server 2008 R2 (64-bit)</td></tr><tr><td>86</td><td>Windows Server 2008 R2 (64-bit) + SQL Server 2008 R2 Standard</td></tr><tr><td>89</td><td>Windows Server 2008 R2 (64-bit) + SQL Server 2008 R2 Web</td></tr><tr><td>91</td><td>Windows Server 2008 R2 (64-bit) + SQL Server 2012 Standard</td></tr><tr><td>92</td><td>Windows Server 2008 R2 (64-bit) + SQL Server 2012 Web</td></tr><tr><td>31</td><td>Windows Server 2008 SP2 (32-bit)</td></tr><tr><td>56</td><td>Windows Server 2008 SP2 (32-bit) + SQL Server 2008 R2 Standard</td></tr><tr><td>24</td><td>Windows Server 2008 SP2 (64-bit)</td></tr><tr><td>57</td><td>Windows Server 2008 SP2 (64-bit) + SQL Server 2008 R2 Standard</td></tr><tr><td>109</td><td>openSUSE 12</td></tr>
</table>


### Some flavor ids

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


# vSphere
* **host**: vSphere host name
* **datacenter**: vSphere datacenter where vms should be started
* **username**: vSphere username
* **password**: vSphere password
* **template_name**: name of the vm to use as a template. Must be defined as template in vSphere.

# License
Apache 2.0 License

<http://www.apache.org/licenses/LICENSE-2.0.html>

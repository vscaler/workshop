# vScaler HPC on OpenStack Workshop

In this workshop we will shall attempt the following

1. Install an OpenStack all-in-one environment 
2. Create a 2 node virtual cluster on top of our OpenStack environment 
3. Run some workload in a Singularity Container 

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [vScaler HPC on OpenStack Workshop](#vscaler-hpc-on-openstack-workshop)
  - [Disable selinux on both nodes](#disable-selinux-on-both-nodes)
  - [Install docker and some packages](#install-docker-and-some-packages)
  - [Working with Screen](#working-with-screen)
- [Setup the deploy container](#setup-the-deploy-container)
  - [Create the base configuration files.](#create-the-base-configuration-files)
  - [Create the globals.yml configuration file](#create-the-globalsyml-configuration-file)
  - [Setup the ansible inventory file.](#setup-the-ansible-inventory-file)
  - [Restart docker container with configiration files mounted](#restart-docker-container-with-configiration-files-mounted)
  - [Generate passwords for all the OpenStack services](#generate-passwords-for-all-the-openstack-services)
  - [Ping checks](#ping-checks)
  - [Bootstrap target AIO node](#bootstrap-target-aio-node)
  - [Run the deploy prechecks](#run-the-deploy-prechecks)
  - [Pull the images down](#pull-the-images-down)
  - [Ready to deploy!](#ready-to-deploy)
  - [Create adminrc shell file](#create-adminrc-shell-file)
  - [Check the OpenStack environmnet](#check-the-openstack-environmnet)
  - [Setup the initial OpenStack environment](#setup-the-initial-openstack-environment)
  - [Run the init-runonce script](#run-the-init-runonce-script)
  - [Create first VM](#create-first-vm)
  - [Failure to create VM](#failure-to-create-vm)
  - [Update the OpenStack configuration](#update-the-openstack-configuration)
  - [Verify the reconfiguration](#verify-the-reconfiguration)
  - [Create VM - Take#2](#create-vm---take2)
  - [Access the VM](#access-the-vm)
  - [Import Centos7 images](#import-centos7-images)
  - [Create our cluster controller and compute node](#create-our-cluster-controller-and-compute-node)
- [Time to deploy the HPC Cluster](#time-to-deploy-the-hpc-cluster)
  - [Setup the Centos VM nodes as we need](#setup-the-centos-vm-nodes-as-we-need)
  - [Setup to use local repo](#setup-to-use-local-repo)
  - [Generate /etc/hosts](#generate-etchosts)
  - [Setup passwordless access between the nodes](#setup-passwordless-access-between-the-nodes)
  - [Permit root access to the cloud images](#permit-root-access-to-the-cloud-images)
  - [Install some prereqs and clone repo](#install-some-prereqs-and-clone-repo)
  - [Setup some more prereqs](#setup-some-more-prereqs)
  - [Modify the ansible setup](#modify-the-ansible-setup)
  - [Ansible configure the controller / headnode](#ansible-configure-the-controller--headnode)
  - [Ansible configure the compute node](#ansible-configure-the-compute-node)
  - [Check the status of SLURM](#check-the-status-of-slurm)
- [Execute jobs with Singularity](#execute-jobs-with-singularity)
  - [Run an app from Singularity hub](#run-an-app-from-singularity-hub)
  - [Run an app from Dockerhub](#run-an-app-from-dockerhub)
  - [Explore the container](#explore-the-container)
  - [Install an updated Python](#install-an-updated-python)
  - [Install R](#install-r)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->


Ok, so to start with lets make sure we can all access the VMs provided for the lab environment and get the baseline configuration in place to allow us progress. Details for access will be provided by the instrutor. You should have access to 2 VMs. One VM ```vscaler-kolla-deploy-XX``` and ```vscaler-openstack-aio-YY```. These nodes are refered to as ```deploy``` and ```aio``` from here on in. (aio =  AllInOne)

> Note: All commands should be run by root unless otherwise stated. You'll need to login as centos and then ```sudo su -```

## Disable selinux on both nodes
```bash
# Run this on both deploy and aio nodes
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux 
```


## Install docker and some packages
```bash
# Install on deploy node only
yum -y install docker vim screen
systemctl start docker
````

## Bring up the cloud interface on the aio node

eth1 will be used as the cloud network and needs to be brought to an UP state before we configure the cloud. 

```bash
# aio node
ip link set dev eth1 up 
```

## Working with Screen

Wifi drops are painfully frequent - dont let it ruin your good work. Get working in screen (or tmux) so you can reattach in the event of any connectivity issues. 

```bash
# Screen basics
screen -S vscaler
(ctrl + a, ctrl + d)
screen -r vscaler
```

## Setup the deploy container
Lets pull our deployment container and get it tagged and ready for action.
```bash
# on deploy node
docker pull registry.vscaler.com:5000/kolla/kolla-deploy:stein
docker tag registry.vscaler.com:5000/kolla/kolla-deploy:stein kolla-deploy
docker create --name kolla-deploy --hostname kolla-deploy kolla-deploy 
```

## Create the base configuration files. 

Our deployment system is guided by a number of configuiration. We copy the default files across from the deploy container and populate them with some sensible defaults.

> Note: Keep the naming conventions here. We mount these directories back into the container a little later on so if your directory has unique naming some steps will fail! You have been warned! 

```bash
# on deploy node
mkdir ~/kolla
docker cp kolla-deploy:/kolla/kolla-ansible/etc/kolla/passwords.yml ~/kolla
docker cp kolla-deploy:/kolla/kolla-ansible/etc/kolla/globals.yml ~/kolla
docker cp kolla-deploy:/kolla/kolla-ansible/ansible/inventory/all-in-one ~/kolla
```

## Create the globals.yml configuration file

The file ```~/kolla/globals.yml' holds the values for our clouds base configuration. Let update that with some parameters to guide the installation process.  

> Note: We use an IP address in here from the ```aio``` node. SSH to that system and capture the ```eth0``` ip address using the command ```ip addrr```

```bash
[root@vscaler-kolla-deploy ~/kolla]# egrep -v '(^#|^$)' globals.yml
---
openstack_release: "stein"
---
kolla_internal_vip_address: "192.168.17.59" # <---  this needs to be the aio ip addr
---
docker_registry: "registry.vscaler.com:5000"
---
network_interface: "eth0"
neutron_external_interface: "eth1"
neutron_type_drivers: "local,flat,vlan,vxlan"
neutron_tenant_network_types: "local"
---
enable_haproxy: "no"
# rest of file is ok leave alone
```

## Setup the ansible inventory file. 

We need to update the hostname and change the ansible_connection to ssh (from local) 

Edit the inventory file ```~/kolla/all-in-one```
```bash
[control]
openstack-aio       ansible_connection=ssh

[network]
openstack-aio       ansible_connection=ssh

[compute]
openstack-aio       ansible_connection=ssh

[storage]
openstack-aio       ansible_connection=ssh

[monitoring]
openstack-aio       ansible_connection=ssh

[deployment]
openstack-aio       ansible_connection=ssh
```

## Restart docker container with configiration files mounted 

Remove the existing deploy container and restart it passing the configuration files through to the container 
```bash
docker rm -f kolla-deploy 
docker run --name kolla-deploy --hostname kolla-deploy --net=host -v /root/kolla/:/etc/kolla/ -v /root/.ssh:/root/.ssh -d -it kolla-deploy bash 
```

> FIX: Python-requests needs removing on ```openstack-aio``` node
```bash
# On the aio node 
rpm -e --nodeps  python-requests
```

## Generate passwords for all the OpenStack services 
Each of the services will have their own databases/tables in the backend database. We can use a script to generate passwords for all of these services. 

```bash
# Check the default settings - no passwords populated 
cat kolla/passwords.yml 
docker exec -it kolla-deploy generate_passwords.py
# now we should see lots of passwords generated 
cat kolla/passwords.yml 
```

## Ping checks

Let make sure we can ping the target host
```bash
docker exec -it kolla-deploy ansible -i /etc/kolla/all-in-one all -m ping 
```

## Bootstrap target AIO node

The bootstrap stage installs all the base packages required to take the centos minimal install to a system ready to have OpenStack deployed on it. This step may take up to 10 minutes. 

```bash
docker exec -it kolla-deploy kolla-ansible -i  /etc/kolla/all-in-one  bootstrap-servers 
```

## Run the deploy prechecks

There is a final stage before we do the deploy which will do some final verifcations on the system to ensure its ready and setup correctly before we deploy. 

```bash
docker exec -it kolla-deploy kolla-ansible -i  /etc/kolla/all-in-one prechecks
```
## Pull the images down
We use a number of containers during the deployment, each service has its own container and we pull these down before the deployment. Depending on the size of the class this can take some time as well. Each node will upll multiple GBs of containers as part of this step.

Before we pull the container images lets just take a quick look at whats there and track the pull progress. 

> Note: In the next step we jump from the ```deploy``` node to the ```aio``` node and back again.

```bash
# on the openstack-aio node
[aio]$ docker images
# back to the deploy node
[deploy]$ docker exec -it kolla-deploy kolla-ansible -i  /etc/kolla/all-in-one pull
# check the images in another screen terminal to see the images downloading
[aio]$ docker images
```
## Ready to deploy!

At this stage we are now ready to start the deploy. This step can take some time, up to an hour, so its an ideal break time.. COFFEE!
```bash
# check the docker processes that are running on the aio world
[aio]$ docker ps 
[deploy]$ docker exec -it kolla-deploy kolla-ansible -i  /etc/kolla/all-in-one deploy
[aio] watch -n 10 docker ps
```
Hopefully at this stage the deployment has gone through successfully. You'll be presented with a summary of the deploy and timings in ansible from the deployment. Keep at eye on the error count. It should ready ```errros=0```

## Create adminrc shell file

To use the openstack CLI utility we need a source file with the user / admin configuraiton parameters. 
```bash
# Run this on the deploy node
# this creates the admin-openrc.sh file 
[aio]$ docker exec -it kolla-deploy kolla-ansible -i  /etc/kolla/all-in-one post-deploy 
# verify the file
cat ~/kolla/admin-openrc.sh
```
## Check the OpenStack environmnet
Let use the openstack CLI utility to explore the current setup of our OpenStack environment.
```bash
# run on the deploy node
# lets drop to bash in the container and try a few openstack commands 
docker exec -it kolla-deploy bash
source /etc/kolla/admin-openrc.sh
openstack hypervisor list
openstack server list
openstack image list 
openstack flavor list 
openstack network list 
# so not much there really!
```

## Setup the initial OpenStack environment 

We have an ```init-runonce``` script which sets up the environment. Take a look through this file and examine it. Its a bash script and it runs a lot of ```openstack``` commands 

> Note: The EXT_NET_RANGE needs to be partitioned across all users in the class. MAke sure you check the etherpad for ranges to use for each VM. 

```bash
# so lets copy it out of the container first to edit it
docker cp kolla-deploy:/kolla/kolla-ansible/tools/init-runonce ~/kolla/
vi ~/kolla/init-runonce

# edit the network public settings - have a little look through 
EXT_NET_CIDR='192.168.10/24'
EXT_NET_RANGE='start=192.168.10.200,end=192.168.10.210'
EXT_NET_GATEWAY='192.168.10.1'
```
## Run the init-runonce script 

```bash
# on the deploy node
docker exec -it kolla-deploy bash
source /etc/kolla/admin-openrc.sh 
/etc/kolla/init-runonce 
```

## Create first VM
The init-runonce script should complete without errors and present you with a command to spin up your first VM
```bash
# execure from inside the deploy container - continues from last step. 
openstack server create \
    --image cirros \
    --flavor m1.tiny \
    --key-name mykey \
    --network demo-net \
    demo1

# To check the status of the server 
openstack server list
openstack server show demo1
```

## Failure to create VM

Whooops - fail!!! So where did we go wrong? Lets dig into the logs a little...

```bash
# ssh on to the openstack aio node) 
cd /var/lib/docker/volumes/kolla_logs/_data/nova/
grep -i error *
```

So we couldnt find a hypervisor with KVM capability... Ah we're in the VM, we need to use qemu virtualisation... 

## Update the OpenStack configuration

Check the VM for hardware accelerated virtualisation support. this command will confirm there is no hardware accelerated virtualisation available - so we need to implement software virtualisation with qemu

```bash
egrep '(vmx|svm)' /proc/cpuinfo
```

Lets take a look at the current node (compute) configuration file. 

```bash
# on the aio node
vi /etc/kolla/nova-compute/nova.conf
# search for section [libvirt] 
virt_type = kvm
# this needs to change to 
virt_type = qemu
# time to reconfigure openstack...


## Reconfigure 

Jump back to the deploy node - outside of kolla-deploy container

```bash
# deploy node
mkdir ~/kolla/config 
# this will be /etc/kolla/config in our container remember
vi ~/kolla/config/nova.conf
[libvirt]
virt_type = qemu
```

We can run a reconfigure which distributes the configuration files across the system and restarts necessary services.

> Note: Add a ```-t nova``` tag to prevent the full cloud being reconfigured which can save a good chunk of time

```bash
docker exec -it kolla-deploy kolla-ansible -i  /etc/kolla/all-in-one reconfigure -t nova 
```

## Verify the reconfiguration

Lets jump back over to the ```openstack aio``` node and take a look at the nova.conf in nova-compute

```bash
# on aio node 
grep virt_type  /etc/kolla/nova-compute/nova.conf 
# ah so nova.conf is updated with virt_type. Let confirm this in the nova_compute container as well
docker exec -it nova_compute grep virt_type /etc/nova/nova.conf 

# and you'll also notice the nova container was restarted as the nova configuration file was updated. 
ssh openstack-aio docker ps 
ssh openstack-aio docker ps '| grep nova_compute'
```

## Create VM - Take#2

Ok lets try and spin up a VM again

```bash
docker exec -it kolla-deploy bash
source /etc/kolla/admin-openrc.sh
openstack server list
openstack server delete demo1
openstack server create \
    --image cirros \
    --flavor m1.tiny \
    --key-name mykey \
    --network demo-net \
    demo1
```


After a short while we should see an ACTIVE VM
```bash
root@kolla-deploy:/kolla# openstack server list
+--------------------------------------+-------+--------+---------------------+--------+---------+
| ID                                   | Name  | Status | Networks            | Image  | Flavor  |
+--------------------------------------+-------+--------+---------------------+--------+---------+
| 28b0ab7b-114c-4090-9a2d-6f6692b524ea | demo1 | ACTIVE | demo-net=10.0.0.211 | cirros | m1.tiny |
+--------------------------------------+-------+--------+---------------------+--------+---------+
```

> Note: You should be able to check all of this in the web portal as well. Hit the floating IP for your aio server and login with the credentials in /etc/kolla/admin-openrc.sh

## Access the VM

Here we are going to take advantage of the ```ip netns``` IP network namespaces to drop into the cloud demo-net where the VM is hosted. 

> Note: Here we use a qrouter UUID which will be unique to your environment. Please take a note of it and be careful with the commands. 

> Note: Likewise with the IP address. Make sure that is copied from the ```openstack server list``` output in the prior step.

```bash
# on the openstack-aio node
ip netns
ip netns exec qrouter-XXXXXX ping 10.0.0.211
ip netns exec qrouter-XXXXXX ssh cirros@10.0.0.211 #Pass gocubsgo
# ping the outside world $ ping 8.8.8.8 # Note: Port security disabled required - if issues speak to instructor! 
```

## Import Centos7 images 

To run our HPC environment, we will need to build on Centos7 minimal so lets get and import that into glance (image service for OpenStack)

```bash
# lets add centos image
# back to deploy node
curl -O http://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2.xz
unxz CentOS-7-x86_64-GenericCloud.qcow2.xz
mv CentOS-7-x86_64-GenericCloud.qcow2 ~/kolla/
```

Copy across ssh keys to the openstack-aio node (from the deploy node) 
```bash
scp ~/.ssh/id_rsa* vscaler-openstack-aio:.ssh/
```

Before we go and create the image lets import into glance 
```bash
docker exec -it kolla-deploy bash
source /etc/kolla/admin-openrc.sh
cd /etc/kolla
openstack image create --container-format bare --disk-format qcow2 --file CentOS-7-x86_64-GenericCloud.qcow2 CentOS-7
```

Lets confirm our flavors and images 
```bash
openstack flavor list
openstack image list
```


## Create our cluster controller and compute node

Create 2 centos images - one as the headnode (vcontroller) - one as compute (node0001) 

> Note: Dont be a hero - keep the naming convention as this is built into the ansible we will be using later on!
>  headnode = vcontroller
>  computenode = node0001

```bash
# drop to deploy container
openstack server create --image CentOS-7 --flavor m1.medium --key-name mykey --network demo-net vcontroller
openstack server create --image CentOS-7 --flavor m1.medium --key-name mykey --network demo-net node0001   
```

Check the server status

```bash
# Lets go and access the vcontrolelr node
root@kolla-deploy:/kolla# openstack server list
+--------------------------------------+-------------+--------+---------------------+----------+-----------+
| ID                                   | Name        | Status | Networks            | Image    | Flavor    |
+--------------------------------------+-------------+--------+---------------------+----------+-----------+
| af0448c9-7835-415f-be32-02f220d0fd28 | node0001    | ACTIVE | demo-net=10.0.0.232 | CentOS-7 | m1.medium |
| 7f618933-c2c9-4848-a3b7-b753e4f336e9 | vcontroller | ACTIVE | demo-net=10.0.0.149 | CentOS-7 | m1.medium |
+--------------------------------------+-------------+--------+---------------------+----------+-----------+
root@kolla-deploy:/kolla# exit
exit
[root@vscaler-kolla-deploy ~]# ssh aioo 
Last login: Wed Dec  4 09:17:12 2019 from 192.168.17.246
[root@vscaler-openstack-aio ~]# ip netns exec qrouter-83e3dde7-5b9f-4f4d-9d47-111cc2daf219 ssh centos@10.0.0.149
The authenticity of host '10.0.0.149 (10.0.0.149)' can't be established.
ECDSA key fingerprint is SHA256:jwxtrTQpvFAvTUL2NYmE+8EZBLoEyE3N59UAMyS3hto.
ECDSA key fingerprint is MD5:b2:c4:79:7d:03:49:6d:ea:9a:06:1f:7e:4c:a5:95:64.
Are you sure you want to continue connecting (yes/no)? yes
Warning: Permanently added '10.0.0.149' (ECDSA) to the list of known hosts.
[centos@vcontroller ~]$ 
```


# Time to deploy the HPC Cluster
Step 2: In this phase of the workshop we install a 2 node cluster. There's a headnode ```vcontroller``` and a compute node ```node0001``` which are based on centos minimal images. We will be using ansible to configure the nodes. 

For more information about the underlying HPC system, please check out the openhpc website: http://www.openhpc.community

## Setup the Centos VM nodes as we need 
```bash
# Disable SELinux
setenforce 0 
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux 
```

## Setup to use local repo
Hopefully youve not snuck ahead and tried to install packages already. If you have please clean out the yum cache as we use our own local repos as below. 

```bash
echo "95.154.198.10   repomirror" >> /etc/hosts
cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.orig
curl http://repomirror/CentOS/CentOS-Base.repo >/etc/yum.repos.d/CentOS-Base.repo
curl http://repomirror/epel/epel.repo > /etc/yum.repos.d/epel.repo
```

## Generate /etc/hosts 

Setup the /etc/hosts file on both nodes (vcontroller / node0001)

> Note: Pay close attention to IP addresses below, dont blindly copy

```bash 
192.168.17.40   vcontroller.cluster vcontroller vc
192.168.17.184  node0001.cluster node0001 n0001
```

## Setup passwordless access between the nodes

```bash
# ssh to each node to add to known_hosts
[root@vscaler-openstack-aio ~]# ip netns exec qrouter-83e3dde7-5b9f-4f4d-9d47-111cc2daf219 scp ~/.ssh/id_rsa* centos@10.0.0.149:
id_rsa                                                                                                                                                      100% 1679     7.2KB/s   00:00    
id_rsa.pub                                                                                                                                                  100%  417    72.2KB/s   00:00    
[root@vcontroller ~]# 
```

## Permit root access to the cloud images 

By default the centos cloud images dont allow root access so lets fix that 
```bash
[root@vcontroller ~]# ssh node0001
The authenticity of host 'node0001 (10.0.0.232)' can't be established.
ECDSA key fingerprint is SHA256:vyq5JFF5HkicP563m/ErUvNCjJHfqbNffxG0p+Q/b68.
ECDSA key fingerprint is MD5:c0:46:97:a0:2d:dc:27:dd:69:78:e9:65:9d:b9:7e:0d.
Are you sure you want to continue connecting (yes/no)? yes
Warning: Permanently added 'node0001,10.0.0.232' (ECDSA) to the list of known hosts.
Please login as the user "centos" rather than the user "root".

Connection to node0001 closed.
[root@vcontroller ~]# ssh centos@node0001
[centos@node0001 ~]$ sudo su - 
Last login: Wed Dec  4 09:31:02 UTC 2019 from 10.0.0.149 on pts/0
[root@node0001 ~]# cat .ssh/authorized_keys 
no-port-forwarding,no-agent-forwarding,no-X11-forwarding,command="echo 'Please login as the user \"centos\" rather than the user \"root\".';echo;sleep 10" ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDF1B5WaCkQq9Fs3S6Z07bh2rl1nfqYcDvviOLmUZDs5G8fHNWlJIJVqxPfqvD1cLW/kjmUcjs9dXGzaA/ZIkB+H63pAfoFUI+teoX+fBaSlm3hjNJpcPyA0KJAT85D42MZuu3bePjq3emm7nH4/P1lzWzss4Vnxg/zAfxp0lLGOQ4y2cVFOHKpeHRc6R06yCPTzZkvARpnQea0YNVHzLxt+5RbyMwEPuqUZjVfn5F2i2KxcBVTi/CR9nbKJWy+v/PsTizJyWIxU0ndYHaK+97fR+sj37SIaGOWvbnZeOJ21cb97rWQQqVfuXAay0bgsN5wXvp+cGpZyMzaSNnTVZn9 root@vscaler-kolla-deploy.novalocal
[root@node0001 ~]# vi .ssh/authorized_keys 
[root@node0001 ~]# cat .ssh/authorized_keys 
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDF1B5WaCkQq9Fs3S6Z07bh2rl1nfqYcDvviOLmUZDs5G8fHNWlJIJVqxPfqvD1cLW/kjmUcjs9dXGzaA/ZIkB+H63pAfoFUI+teoX+fBaSlm3hjNJpcPyA0KJAT85D42MZuu3bePjq3emm7nH4/P1lzWzss4Vnxg/zAfxp0lLGOQ4y2cVFOHKpeHRc6R06yCPTzZkvARpnQea0YNVHzLxt+5RbyMwEPuqUZjVfn5F2i2KxcBVTi/CR9nbKJWy+v/PsTizJyWIxU0ndYHaK+97fR+sj37SIaGOWvbnZeOJ21cb97rWQQqVfuXAay0bgsN5wXvp+cGpZyMzaSNnTVZn9 root@vscaler-kolla-deploy.novalocal
[root@node0001 ~]# ^C
[root@node0001 ~]# logout
[centos@node0001 ~]$ ^C
[centos@node0001 ~]$ logout
Connection to node0001 closed.
[root@vcontroller ~]# ssh node0001
Last login: Wed Dec  4 09:31:16 2019
[root@node0001 ~]# 
```

Repeat this proceedure to allow the system access itself, i.e:  vcontroller -> vcontroller

```bash
[root@vcontroller ~]# vi ~/.ssh/authorized_keys 
[root@vcontroller ~]# ssh vcontroller
Last login: Wed Dec  4 09:35:18 2019 from vcontroller
[root@vcontroller ~]# 
```

## Install some prereqs and clone repo

> Note: dont forget the ```.``` in the git clone command 

```bash
# on vcontroller
yum -y install ansible git screen vim 
mkdir -p /opt/vScaler
git clone https://github.com/vscaler/workshop .
```


## Setup some more prereqs
```bash
ansible-galaxy install OndrejHome.pcs-modules-2
ansible-galaxy install ome.network
```

## Modify the ansible setup

First of all we setup the hosts file / inventory file. 
```bash
cd /opt/vScaler/site
vi hosts # (insert correct name if needed) comment out portal 

# edit group_vars/all: 
trix_ctrl1_ip: 10.0.0.149  # <--- Make sure this is the correct IP address, needs to be the vcontroller IP
trix_ctrl1_bmcip: 10.148.255.254
trix_ctrl1_heartbeat_ip: 10.146.255.254
trix_ctrl1_hostname: vcontroller

trix_cluster_net: 10.0.0.0
trix_cluster_netprefix: 24
```

> Note: Be careful not to ```ctrl+c``` out of the ansible playbook. You can upset things if only partially completed. Let if fail or complete to be safe. 

## Ansible configure the controller / headnode
```bash
# from the /opt/vScaler/site directory
ansible-playbook controller.yml
# or if you get prompted by SSH about host key checks
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook controller.yml
```

## Ansible configure the compute node 
```bash
ansible-playbook static_compute.yml 
```

## Check the status of SLURM 
Make sure SLURM is online and working ok 

```bash
sinfo 
squeue
```
# Execute jobs with Singularity

Step #3 - As part of this stage of the workshop we will run some Singularity application containers 

For more information on Singularity, please visit: https://sylabs.io

## Run an app from Singularity hub
```bash
module load singularity
singularity pull shub://vsoch/hello-world
singularity run ./hello-world_latest.sif 
```

## Run an app from Dockerhub

Now lets do the same thing but import from dockerhub
```bash
singularity pull docker://godlovedc/lolcow
singularity run ./lolcow_latest.sif
```

## Explore the container

Drop in to the shell and show the OS version 
```bash
singularity shell ./lolcow_latest.sif 
cat /etc/os-release
```

## Install an updated Python
```bash
singularity pull docker://python:3.5.2
singularity exec ./python_3.5.2.sif python -V 
```

## Install R
```bash
singularity pull docker://r-base
singularity pull docker://r-base:3.6.1
```

# vScaler HPC on OpenStack Workshop

In this workshop we will shall attempt the following

1. Install an OpenStack all-in-one environment 
2. Create a 2 node virtual cluster on top of our OpenStack environment 
3. Run some workload in a Singularity Container 

Ok, so to start with lets make sure we can all access the VMs provided for the lab environment and get the baseline configuration in place to allow us progress. Details for access will be provided by the instrutor. You should have access to 2 VMs. One vscaler-kolla-deploy-XX and one vscaler-openstack-aio-YY.

## Lets disable selinux on both nodes
```bash
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux 
```


## Install docker and some packages
```bash
yum -y install docker vim screen
systemctl start docker
````

## Working with Screen

wifi drops are painfully frequent - dont let it ruin your good work. Get working in screen (or tmux) so you can reattach in the event of any connectivity issues. 
```bash
# Screen basics
screen -S vscaler
(ctrl + a, ctrl + d)
screen -r vscaler
```


docker pull registry.vscaler.com:5000/kolla/kolla-deploy:stein
docker tag registry.vscaler.com:5000/kolla/kolla-deploy:stein kolla-deploy

docker create --name kolla-deploy --hostname kolla-deploy kolla-deploy 

mkdir /root/kolla

docker cp kolla-deploy:/kolla/kolla-ansible/etc/kolla/passwords.yml ~/kolla
docker cp kolla-deploy:/kolla/kolla-ansible/etc/kolla/globals.yml ~/kolla
docker cp kolla-deploy:/kolla/kolla-ansible/ansible/inventory/all-in-one ~/kolla


[root@test-openstack kolla]# egrep -v '(^#|^$)' globals.yml
---
openstack_release: "stein"
kolla_internal_vip_address: "192.168.17.59" # <---  this needs to be the aio ip addr
docker_registry: "registry.vscaler.com:5000"
network_interface: "eth0"
neutron_external_interface: "eth1"
neutron_type_drivers: "local,flat,vlan,vxlan"
neutron_tenant_network_types: "local"
enable_haproxy: "no"
# rest of file is ok leave alone


# on second host - disable selinux / setup /etc/hosts file / setup passwordless access between the two hosts. 
# disable selinux
# give system a hostname in /etc/hosts
# setup passwordless access


# edit inventory
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

# mount the kolla config dirs 


docker rm -f kolla-deploy 
# docker run --name kolla-deploy --hostname kolla-deploy -v /root/kolla/:/etc/kolla/ -d -it kolla-deploy bash 
# docker run --name kolla-deploy --hostname kolla-deploy --net=host -v /root/kolla/:/etc/kolla/ -d -it kolla-deploy bash 
# need networking to ssh 
docker run --name kolla-deploy --hostname kolla-deploy --net=host -v /root/kolla/:/etc/kolla/ -v /root/.ssh:/root/.ssh -d -it kolla-deploy bash 

# FIX: Python-requests needs removing / on openstack-aio node
rpm -e --nodeps  python-requests (on openstack deploy not kolla-deploy)

cat kolla/passwords.yml 
docker exec -it kolla-deploy generate_passwords.py
cat kolla/passwords.yml 

docker exec -it kolla-deploy ansible -i /etc/kolla/all-in-one all -m ping 

docker exec -it kolla-deploy kolla-ansible -i  /etc/kolla/all-in-one  bootstrap-servers 

docker exec -it kolla-deploy kolla-ansible -i  /etc/kolla/all-in-one prechecks

ssh openstack-aio docker images
docker exec -it kolla-deploy kolla-ansible -i  /etc/kolla/all-in-one pull
ssh openstack-aio docker images

ssh openstack-aio docker ps 
docker exec -it kolla-deploy kolla-ansible -i  /etc/kolla/all-in-one deploy
ssh openstack-aio docker ps

# this creates the admin-openrc.sh file 
docker exec -it kolla-deploy kolla-ansible -i  /etc/kolla/all-in-one post-deploy 

# verify the file
cat ~/kolla/admin-openrc.sh

# lets drop to bash in the container and try a few openstack commands 
docker exec -it kolla-deploy bash
source /etc/kolla/admin-openrc.sh
openstack hypervisor list
openstack server list
openstack image list 
openstack flavor list 
openstack network list 

# so not much there really! lets populate that and spin up a cirros image to test openstack 

# lets edit 
/kolla/kolla-ansible/tools/init-runonce

so lets copy it out of the container first to edit it
docker cp kolla-deploy:/kolla/kolla-ansible/tools/init-runonce ~/kolla/
# edit the network public settings - have a little look through 

EXT_NET_CIDR='192.168.10/24'
EXT_NET_RANGE='start=192.168.10.200,end=192.168.10.210'
EXT_NET_GATEWAY='192.168.10.1'

docker exec -it kolla-deploy bash
source /etc/kolla/admin-openrc.sh 
/etc/kolla/init-runonce 

# should complete without errors and present you with a command to spin up your first VM
openstack server create \
    --image cirros \
    --flavor m1.tiny \
    --key-name mykey \
    --network demo-net \
    demo1

# Whooops - fail!!! So where did we go wrong? lets dig into the logs a little

# ssh on to the openstack node (not the kolla deploy node) 

cd /var/lib/docker/volumes/kolla_logs/_data/nova/
grep -i error *

# So we couldnt find a hypervisor with KVM capability... Ah we're in the VM, we need to use qemu virtualisation... 

# this command will confirm there is no hardware accelerated virtualisation available - so we need to implement software virtualisation with qemu
egrep '(vmx|svm)' /proc/cpuinfo

# then check /etc/kolla/nova-compute/nova.conf
# section [libvirt] 
# virt_type = kvm
# this needs to change to 
# virt_type = qemu
# time to reconfigure openstack...
# back to the kolla-deploy node - outside of kolla-deploy container

mkdir ~/kolla/config 
# this will be /etc/kolla/config in our container remember
vi ~/kolla/config/nova.conf
[libvirt]
virt_type = qemu

# with the nova tag instead of a full reconfigure
docker exec -it kolla-deploy kolla-ansible -i  /etc/kolla/all-in-one reconfigure -t nova 

# lets jump back over to the openstack node and take a look at the nova.conf in nova-compute
# ah so nova.conf is updated with virt_type

# and you'll also notice the nova container was restarted as the nova configuration file was updated. 
ssh openstack-aio docker ps 
ssh openstack-aio docker ps '| grep nova_compute'

# ok lets try and spin up a VM again
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

# after a short while we should see 
root@kolla-deploy:/kolla# openstack server list
+--------------------------------------+-------+--------+---------------------+--------+---------+
| ID                                   | Name  | Status | Networks            | Image  | Flavor  |
+--------------------------------------+-------+--------+---------------------+--------+---------+
| 28b0ab7b-114c-4090-9a2d-6f6692b524ea | demo1 | ACTIVE | demo-net=10.0.0.211 | cirros | m1.tiny |
+--------------------------------------+-------+--------+---------------------+--------+---------+

# check it out in the portal as well - hit the floating IP for your server and login with the credentials in /etc/kolla/admin-openrc.sh

# on the openstack-aio node
ip netns
ip netns exec qrouter-XXXXXX ping 10.0.0.211
ip netns exec qrouter-XXXXXX ssh cirros@10.0.0.211 #Pass gocubsgo

ping the outside world (Note: Port security disabled required) 

# lets add centos image
# back to kolla deploy 
curl -O http://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2.xz
unxz CentOS-7-x86_64-GenericCloud.qcow2.xz
mv CentOS-7-x86_64-GenericCloud.qcow2 ~/kolla/

# copy across ssh keys to the openstack-aio node (from the deploy node) 
scp ~/.ssh/id_rsa* vscaler-openstack-aio:.ssh/

# before we go and create the 
docker exec -it kolla-deploy bash
source /etc/kolla/admin-openrc.sh
cd /etc/kolla
openstack image create --container-format bare --disk-format qcow2 --file CentOS-7-x86_64-GenericCloud.qcow2 CentOS-7

# ok lets confirm our flavors and images 
openstack flavor list
openstack image list

# and lets create 2 centos images - one as the headnode - one as compute 
# dont be a hero - keep the naming convention as this is built into the ansible we will be using later on!
# headnode = vcontroller
# computenode = node0001
openstack server create --image CentOS-7 --flavor m1.medium --key-name mykey --network demo-net vcontroller
openstack server create --image CentOS-7 --flavor m1.medium --key-name mykey --network demo-net node0001   

# lets go and access the vcontrolelr node
root@kolla-deploy:/kolla# openstack server list
+--------------------------------------+-------------+--------+---------------------+----------+-----------+
| ID                                   | Name        | Status | Networks            | Image    | Flavor    |
+--------------------------------------+-------------+--------+---------------------+----------+-----------+
| af0448c9-7835-415f-be32-02f220d0fd28 | node0001    | ACTIVE | demo-net=10.0.0.232 | CentOS-7 | m1.medium |
| 7f618933-c2c9-4848-a3b7-b753e4f336e9 | vcontroller | ACTIVE | demo-net=10.0.0.149 | CentOS-7 | m1.medium |
+--------------------------------------+-------------+--------+---------------------+----------+-----------+
root@kolla-deploy:/kolla# source /etc/kolla/admin-openrc.sh^C
root@kolla-deploy:/kolla# exit
exit
[root@vscaler-kolla-deploy ~]# ssh vo 
Last login: Wed Dec  4 09:17:12 2019 from 192.168.17.246
[root@vscaler-openstack-aio ~]# ip netns exec qrouter-83e3dde7-5b9f-4f4d-9d47-111cc2daf219 ssh centos@10.0.0.149
The authenticity of host '10.0.0.149 (10.0.0.149)' can't be established.
ECDSA key fingerprint is SHA256:jwxtrTQpvFAvTUL2NYmE+8EZBLoEyE3N59UAMyS3hto.
ECDSA key fingerprint is MD5:b2:c4:79:7d:03:49:6d:ea:9a:06:1f:7e:4c:a5:95:64.
Are you sure you want to continue connecting (yes/no)? yes
Warning: Permanently added '10.0.0.149' (ECDSA) to the list of known hosts.
[centos@vcontroller ~]$ 

##### 
opehpc 

centos minimal 

setenforce 0 
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux 

setup hosts (vcontroller / node0001 ideally) 
192.168.17.40   vcontroller.cluster vcontroller vc
192.168.17.184  node0001.cluster node0001 n0001

setup ssh keys! inc localhost and node0001
ssh to each node to add to known_hosts
[root@vscaler-openstack-aio ~]# ip netns exec qrouter-83e3dde7-5b9f-4f4d-9d47-111cc2daf219 scp ~/.ssh/id_rsa* centos@10.0.0.149:
id_rsa                                                                                                                                                      100% 1679     7.2KB/s   00:00    
id_rsa.pub                                                                                                                                                  100%  417    72.2KB/s   00:00    
[root@vcontroller ~]# 

# by default the centos cloud images dont allow root access so lets fix that 
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

# repeat to allow the system access itself vcontroller -> vcontroller
[root@vcontroller ~]# vi ~/.ssh/authorized_keys 
[root@vcontroller ~]# ssh vcontroller
Last login: Wed Dec  4 09:35:18 2019 from vcontroller
[root@vcontroller ~]# 

# ok lets sync the ansible configuration files

curl http://bostonhpc.co.uk:8081/dp/site.tgz > site2.tgz

tar zxvf into /opt/vScaler

echo "95.154.198.10   repomirror" >> /etc/hosts

cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.orig
curl http://repomirror/CentOS/CentOS-Base.repo >/etc/yum.repos.d/CentOS-Base.repo
curl http://repomirror/epel/epel.repo > /etc/yum.repos.d/epel.repo

yum -y install ansible git 

ansible-galaxy install OndrejHome.pcs-modules-2
ansible-galaxy install ome.network

vi /opt/vScaler/site/hosts (insert correct name if needed) comment out portal 

cd /opt/vScaler/site

edit controller.yml (ssl-cert area!) 

edit group_vars/all: 
trix_ctrl1_ip: 192.168.17.40
trix_ctrl1_bmcip: 10.148.255.254
trix_ctrl1_heartbeat_ip: 10.146.255.254
trix_ctrl1_hostname: vcontroller

trix_cluster_net: 10.0.0.0
trix_cluster_netprefix: 24
# serach antonys cluster

  static_compute_host_name_base: computenode

# mariadb fix 

vi roles/trinity/mariadb/tasks/main.yml 
76 #      check_implicit_admin: yes
uncomment

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook controller.yml

ansible-playbook static_compute.yml 

# to get singularity to work  (take2!)

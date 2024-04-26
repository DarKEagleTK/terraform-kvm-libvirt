# VM Terraform KVM

## How it works

### Version

| | Version |
| :-- | --: |
| Host | Debian 12 |
| Terraform | 1.8.0 |
| qemu-system | 1:7.2+dfsg-7+deb12u5 |
| libvirt | 9.0.0-4 |
| apparmor | 3.0.8-3 |

### Host configuration

We need to change a config file in apparmor to let kvm read and write in our future directory who gonna store all our disk and template.

In the file ``/etc/apparmor.d/libvirt/TEMPLATE.qemu`` :

```bash
profile LIBVIRT_TEMPLATE flags=(attach_disconnected) {
  #include <abstractions/libvirt-qemu>
  /path/to/directory/** rwk,
}
```

### Files Provider

[Libvirt Provider Documentations](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs)

I only successed to make it with a local terraform, so my provider point to the uri ``qemu:///system``. <br>
When I try to make to make it distant, it seems terraform try to take the file and create directory on my local machine.


### Files Variables

```bash
####################### variables.tf #######################
variable "memoryMB" { 
    default = 1024*4 # Define number of RAM
}
variable "cpu" { 
    default = 4 # Define number of VCPUs
}

variable gateway {
  default = "10.99.0.1" # Define gateway
}

variable nameserver {
  default = "192.168.0.254" # Define DNS
}

variable network_name {
  default = "Interne" # Define kvm's network name
}

variable workers_count {
    default = 1 # Define number of VM you want
}
```

- To change the ram, you just need to change the number of multiplication.
- The KVM network name need to be the have the same typo as KVM : virsh net-list
- if you want several machines, the firt will be the 0. If you want to change that, you need to change in the other file ``count.index`` by ``count.index+1`` (not tested)

### Files Storage

This file is the first one you need to pay attention. You need to create the pool to store all the differents disk you will need.

I make it to store it in a directory. The directory doesn't need to be create.

```bash
resource "libvirt_pool" "name_of_the_pool" {
    name = "name_of_the_pool"
    type = "dir"
    path = "/path/to/directory/vm-name_of_the_pool"
}
```

We need to pass the cloud init disk. To have it, you can search ``os cloud init`` in your navigator and take the file ``genericcloud``.

```bash
resource "libvirt_volume" "master_debian11" {
    name = "master_debian11"
    pool = libvirt_pool.name_of_the_pool.name
    source = "/path/to/directory/templates/debian-11-cloud-init-base.qcow2"
}
```

After that, we can create the disk for the virtual machine.

```bash
resource "libvirt_volume" "main_disque" {
    name = "vm-name-00${count.index}-disque"
    pool = libvirt_pool.name_of_the_pool.name
    base_volume_id = libvirt_volume.master_debian11.id
    size = 107374182400 # 100GB
    count = var.workers_count
}
```

The size can rezise the disk, and it is in Bytes.

### File Cloud Init

First, we need to create two files ``cloud_init.cfg`` and ``network_config.cfg``, which contain cloud init configuration and cloud init network configuration.

Here the [Documentation](https://cloudinit.readthedocs.io/en/latest/)

```bash
#Cloud_init.cfg
## Hostname configuration - I use variables to configure it later with terraform
hostname: ${hostname}
fqdn: ${hostname}

## User creation section
users:
  - name: user
    sudo: ALL=(ALL) NOPASSWD:ALL
    home: /home/user
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - key1
      - key2
## Some other configuration : desactivate password authentification in ssh, set password to user
ssh_pwauth: false
disable_root: false
chpasswd:
  list: |
     user:mdp
  expire: false

## first network configuration - set nameservers in resolv.conf. 
manage_etc_hosts: true
manage_resolv_conf: true
resolv_conf:
  nameservers: [ ${nameserver} ]

## packages installation
package_update: true
packages:
  - qemu-guest-agent

## END - reboot after 30s, to apply the network configuration.
final_message: "The system is finally up, after $UPTIME seconds"
power_state:
  mode: reboot
  message: reboot
  timeout: 30
  condition: True
```

```bash
# network_config.cfg
version: 2
ethernets:
  ens3: # ens3 for debian11, eth0 for rocky9
    dhcp4: false
    addresses: [ ${ip} ]
    gateway4: ${gateway}
    nameservers:
      addresses: [ ${nameserver} ]
```

After this, we gonna configure the disk cloud init, and pass the vars.

We start with the user_data part. We specify to terraform where is the file ``cloud_init.cfg`` and we pass the vars. Don't forget to add the count to work with the other system.

```bash
data "template_file" "user_data" {
  template = file("./cloud_init/cloud_init.cfg")
  vars = {
    hostname = "vm-name-00${count.index}"
    fqdn = "vm-name-00${count.index}"
    nameserver = var.nameserver
  }
  count = var.workers_count
}
```

We do the same for the network config file. I pass the IP without var because of some process I didn't automate yet.

```bash
data "template_file" "network_config" {
  template = file("./cloud_init/network_config.cfg")
  vars = {
    ip = "10.99.0.1${count.index}/16"
    gateway = var.gateway
    nameserver = var.nameserver
  }
  count = var.workers_count
}
```

After that, we need to make a little formatting on the user_data part:
```bash
data "template_cloudinit_config" "config" {
  gzip = false
  base64_encode = false
  part {
    filename = "init.cfg"
    content_type = "text/cloud-config"
    content = "${data.template_file.user_data[count.index].rendered}"
  }
  count = var.workers_count
}
``` 

And we can create the cloud init disk in our pool : 
```bash
resource "libvirt_cloudinit_disk" "commoninit" {
  name = "vm-name-00${count.index}-commoninit.iso"
  pool = libvirt_pool.name_of_the_pool.name
  user_data      = data.template_cloudinit_config.config[count.index].rendered
  network_config = data.template_file.network_config[count.index].rendered

  count = var.workers_count

  depends_on = [ libvirt_pool.name_of_the_pool ]
}
```

### File instances

We can create our virtuals machines.

```bash
resource "libvirt_domain" "domain" {
  name = "vm-name-00${count.index}" # Name in KVM
  # ressources of the VM
  memory = var.memoryMB
  vcpu = var.cpu

  # Add disk
  disk {
    volume_id = "${element(libvirt_volume.main_disque.*.id, count.index)}"
  }
  # Network interface
  network_interface {
    network_name = var.network_name
  }

  # Add cloud init disk
  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id
  #qemu agent param don't work
  #qemu_agent = true

  # IMPORTANT
  # VM can hang is a isa-serial is not present at boot time.
  # If you find your CPU 100% and never is available this is why
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
  graphics {
    type = "vnc"
    listen_type = "address"
    autoport = "true"
  }
  cpu {
    mode = "host-passthrough"
  }

  count = var.workers_count
  depends_on = [ libvirt_pool.name_of_the_pool ]
}
```

## Lunch terraform

```bash
terraform init

terraform plan
terraform apply

terraform destroy
```
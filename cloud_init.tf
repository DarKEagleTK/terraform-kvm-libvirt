# initialisation des fichiers cloud inits
data "template_file" "user_data" {
  template = file("./cloud_init/cloud_init.cfg")
  vars = {
    hostname = "vm-name-00${count.index}"
    fqdn = "vm-name-00${count.index}"
    nameserver = var.nameserver
  }
  count = var.workers_count
}
data "template_file" "network_config" {
  template = file("./cloud_init/network_config.cfg")
  vars = {
    ip = "10.99.0.1${count.index}/16"
    gateway = var.gateway
    nameserver = var.nameserver
  }
  count = var.workers_count
}

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

# Creation du disque cloud init
resource "libvirt_cloudinit_disk" "commoninit" {
  name = "vm-name-00${count.index}-commoninit.iso"
  pool = libvirt_pool.name_of_the_pool.name
  user_data      = data.template_cloudinit_config.config[count.index].rendered
  network_config = data.template_file.network_config[count.index].rendered

  count = var.workers_count

  depends_on = [ libvirt_pool.name_of_the_pool ]
}
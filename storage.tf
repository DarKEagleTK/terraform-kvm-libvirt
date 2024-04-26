# Dossier pour les disques
resource "libvirt_pool" "name_of_the_pool" {
    name = "name_of_the_pool"
    type = "dir"
    path = "/path/to/directory/vm-name_of_the_pool"
}

# disque base
resource "libvirt_volume" "master_debian11" {
    name = "master_debian11"
    pool = libvirt_pool.name_of_the_pool.name
    source = "/path/to/directory/templates/debian-11-cloud-init-base.qcow2"
}

# Disque pour la VM
resource "libvirt_volume" "main_disque" {
    name = "vm-name-00${count.index}-disque"
    pool = libvirt_pool.name_of_the_pool.name
    base_volume_id = libvirt_volume.master_debian11.id
    size = 107374182400 # 100Gb
    count = var.workers_count
}
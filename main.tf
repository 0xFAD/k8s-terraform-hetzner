# PROVIDER ----------------------------------------------------------------------------
provider "hcloud" {
  token = var.token
}
# -------------------------------------------------------------------------------------


# SSH-KEY -----------------------------------------------------------------------------
resource "hcloud_ssh_key" "k8s" {
  name       = "k8s"
  public_key = file(var.ssh_public_key)
}
# -------------------------------------------------------------------------------------


# NETWORK -----------------------------------------------------------------------------
resource "hcloud_network" "int_net" {
  name     = "intnet"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "int_subnet" {
  network_id   = hcloud_network.int_net.id
  type         = "server"
  network_zone = "eu-central"
  ip_range     = "10.0.0.0/24"
}
# -------------------------------------------------------------------------------------


# MASTER ------------------------------------------------------------------------------
resource "hcloud_server_network" "cluster_network_master" {
  network_id = hcloud_network.int_net.id
  server_id  = hcloud_server.master.id
  ip         = "10.0.0.2"

  connection {
    type        = "ssh"
    user        = "root"
    host        = hcloud_server.master.ipv4_address
    private_key = file(var.ssh_private_key)
  }

  provisioner "remote-exec" {
    inline = ["bash /tmp/firewall.sh"]
  }

  provisioner "file" {
    source      = "files/services/weave-net.yaml"
    destination = "/tmp/weave-net.yaml"
  }

  provisioner "remote-exec" {
    inline = ["bash /tmp/kubeadm.sh"]
  }

  provisioner "local-exec" {
    command = "bash scripts/copy.sh"

    environment = {
      SSH_PRIVATE_KEY = var.ssh_private_key
      SSH_USERNAME    = "root"
      SSH_HOST        = hcloud_server.master.ipv4_address
      TARGET          = "${path.module}/secrets/"
    }
  }
}

resource "hcloud_server" "master" {
  name        = "master"
  image       = "debian-10"
  server_type = "cpx11"
  location    = "fsn1"
  ssh_keys    = [hcloud_ssh_key.k8s.id]
  labels = {
    node = "master"
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = self.ipv4_address
    private_key = file(var.ssh_private_key)
  }

  provisioner "file" {
    source      = "scripts/init.sh"
    destination = "/tmp/init.sh"
  }

  provisioner "file" {
    source      = "scripts/firewall.sh"
    destination = "/tmp/firewall.sh"
  }

  provisioner "file" {
    source      = "scripts/kubeadm.sh"
    destination = "/tmp/kubeadm.sh"
  }

  provisioner "remote-exec" {
    inline = ["bash /tmp/init.sh"]
  }

  provisioner "file" {
    source      = "files/cluster/init.yaml"
    destination = "/tmp/init.yaml"
  }

  provisioner "file" {
    source      = "files/cluster/kubelet.yaml"
    destination = "/tmp/kubelet.yaml"
  }
}
# -------------------------------------------------------------------------------------


# NODES -------------------------------------------------------------------------------
resource "hcloud_server_network" "cluster_network_node" {
  count      = var.node_count
  network_id = hcloud_network.int_net.id
  server_id  = element(hcloud_server.node.*.id, count.index)
  ip         = "10.0.0.${3 + count.index}"

  connection {
    type        = "ssh"
    user        = "root"
    host        = element(hcloud_server.node.*.ipv4_address, count.index)
    private_key = file(var.ssh_private_key)
  }

  provisioner "remote-exec" {
    inline = ["bash /tmp/firewall.sh"]
  }

  provisioner "remote-exec" {
    inline = ["bash /tmp/kubeadm.sh"]
  }
}

resource "hcloud_server" "node" {
  count       = var.node_count
  name        = "node-${count.index + 1}"
  image       = "debian-10"
  server_type = "cx11"
  location    = "fsn1"
  ssh_keys    = [hcloud_ssh_key.k8s.id]
  depends_on  = [hcloud_server_network.cluster_network_master]
  labels = {
    node = "worker"
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = self.ipv4_address
    private_key = file(var.ssh_private_key)
  }

  provisioner "file" {
    source      = "scripts/init.sh"
    destination = "/tmp/init.sh"
  }

  provisioner "file" {
    source      = "scripts/firewall.sh"
    destination = "/tmp/firewall.sh"
  }

  provisioner "file" {
    source      = "scripts/kubeadm.sh"
    destination = "/tmp/kubeadm.sh"
  }

  provisioner "remote-exec" {
    inline = ["bash /tmp/init.sh"]
  }

  provisioner "file" {
    source      = "files/cluster/join.yaml"
    destination = "/tmp/join.yaml"
  }

  provisioner "file" {
    source      = "files/cluster/kubelet.yaml"
    destination = "/tmp/kubelet.yaml"
  }

  provisioner "file" {
    source      = "secrets/kubeadm_join"
    destination = "/tmp/kubeadm_join"
  }
}
# -------------------------------------------------------------------------------------

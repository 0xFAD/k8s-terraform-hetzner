#!/bin/bash
set -eu

# Upgrade system
apt-get -qq update && apt-get -qq upgrade -y && apt-get -qq install -y apt-transport-https ca-certificates curl software-properties-common

# ---------------------------------------------------------------------------------------------------------------------------------- #
# Installing docker
# ---------------------------------------------------------------------------------------------------------------------------------- #
cat > /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

echo "
Package: docker-ce
Pin: version 19.03.*
Pin-Priority: 1000
" > /etc/apt/preferences.d/docker-ce
curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/debian \
    $(lsb_release -cs) \
    stable"
apt-get -qq update
apt-get -qq install -y docker-ce

cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

systemctl restart docker
# ---------------------------------------------------------------------------------------------------------------------------------- #

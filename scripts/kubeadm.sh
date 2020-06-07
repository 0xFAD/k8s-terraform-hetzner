#!/bin/bash
set -eu

# Installing kube-deps ------------------------------------------------------------------------------------------------------------- #
echo "
Package: kubelet
Pin: version 1.18.*
Pin-Priority: 1000
" > /etc/apt/preferences.d/kubelet

echo "
Package: kubeadm
Pin: version 1.18.*
Pin-Priority: 1000
" > /etc/apt/preferences.d/kubeadm

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get -qq update && apt-get -qq install -y kubelet kubeadm
# ---------------------------------------------------------------------------------------------------------------------------------- #


NODE_NAME=$(hostname)
NODE_PUBLIC_IP=$(hostname -I | awk '{print $1}')
NODE_PRIVATE_IP=$(hostname -I | xargs -n1 | grep '^10\.0\.0\.')


# Kubelet configuration ------------------------------------------------------------------------------------------------------------ #
if [ ! -d /var/lib/kubelet ]; then
  mkdir -p /var/lib/kubelet;
fi

if [ -f /tmp/kubelet.yaml ]; then
  sed -i -e "s/__NODE_PRIVATE_IP__/$NODE_PRIVATE_IP/g" /tmp/kubelet.yaml
  cp /tmp/kubelet.yaml /var/lib/kubelet/config.yaml;
fi

systemctl restart kubelet.service
# ---------------------------------------------------------------------------------------------------------------------------------- #


# Master nodes --------------------------------------------------------------------------------------------------------------------- #
if [[ "$NODE_NAME" == "master" ]]; then
  if [ -f /tmp/init.yaml ]; then
    sed -i -e "s/__NODE_NAME__/$NODE_NAME/g" -e "s/__NODE_PUBLIC_IP__/$NODE_PUBLIC_IP/g" -e "s/__NODE_PRIVATE_IP__/$NODE_PRIVATE_IP/g" /tmp/init.yaml
    echo "---" >> /tmp/init.yaml && cat /tmp/init.yaml /tmp/kubelet.yaml > /tmp/config.yaml

    ufw allow proto tcp to $NODE_PUBLIC_IP port 6443 comment "kube-api-server"
    kubeadm init --config=/tmp/config.yaml

    mkdir -p $HOME/.kube && cp /etc/kubernetes/admin.conf $HOME/.kube/config
    kubeadm token create --print-join-command | xargs -n1 | awk '{if(NR==3||NR==5||NR==7) print $0}' | xargs -n3 > /tmp/kubeadm_join

    systemctl restart kubelet.service

    if [ -f /tmp/weave-net.yaml ]; then
      kubectl apply -f /tmp/weave-net.yaml;
    fi
    
    exit 0;
  fi
fi
# ---------------------------------------------------------------------------------------------------------------------------------- #


# Workers nodes -------------------------------------------------------------------------------------------------------------------- #
if [[ "$(echo $NODE_NAME | grep '^node-')" != "" ]]; then
  if [ -f /tmp/join.yaml ]; then
    ENDPOINT=$(cat /tmp/kubeadm_join | awk '{print $1}')
    TOKEN=$(cat /tmp/kubeadm_join | awk '{print $2}')
    CERT=$(cat /tmp/kubeadm_join | awk '{print $3}')

    sed -i \
      -e "s/__TOKEN__/$TOKEN/g" \
      -e "s/__ENDPOINT__/$ENDPOINT/g" \
      -e "s/__CERT__/$CERT/g" \
      -e "s/__NODE_NAME__/$NODE_NAME/g" \
      -e "s/__NODE_PRIVATE_IP__/$NODE_PRIVATE_IP/g" /tmp/join.yaml

    kubeadm join --config=/tmp/join.yaml

    systemctl restart kubelet.service
    exit 0;
  fi
fi
# ---------------------------------------------------------------------------------------------------------------------------------- #

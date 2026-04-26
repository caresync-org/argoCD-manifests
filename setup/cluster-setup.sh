#!/bin/bash
# =============================================================================
# Kubernetes Cluster Setup Script (kubeadm)
# =============================================================================
# SECTION A: Run on ALL nodes (master + workers)
# SECTION B: Run on MASTER node only
# SECTION C: Run on WORKER nodes only
# =============================================================================

set -e

# =============================================================================
# SECTION A: ALL NODES — Run on master, worker1, and worker2
# =============================================================================

echo "=== [SECTION A] Disabling swap ==="
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "=== [SECTION A] Loading kernel modules ==="
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

echo "=== [SECTION A] Setting sysctl params for Kubernetes networking ==="
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

echo "=== [SECTION A] Installing containerd ==="
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y containerd.io

echo "=== [SECTION A] Configuring containerd with systemd cgroup ==="
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

echo "=== [SECTION A] Installing kubeadm, kubelet, kubectl ==="
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl

echo "=== [SECTION A] Holding kubeadm, kubelet, kubectl versions ==="
sudo apt-mark hold kubelet kubeadm kubectl

echo ""
echo "=== [SECTION A] COMPLETE. Now run SECTION B on MASTER or SECTION C on WORKERS ==="
echo ""

# =============================================================================
# SECTION B: MASTER NODE ONLY
# =============================================================================
# Uncomment the lines below and run only on the master node

# echo "=== [SECTION B] Initializing Kubernetes cluster ==="
# sudo kubeadm init --pod-network-cidr=10.244.0.0/16
#
# echo "=== [SECTION B] Setting up kubectl config for current user ==="
# mkdir -p $HOME/.kube
# sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
# sudo chown $(id -u):$(id -g) $HOME/.kube/config
#
# echo "=== [SECTION B] Installing Weave Net CNI ==="
# kubectl apply -f https://reweave.azurewebsites.net/k8s/v1.29/net.yaml
#
# echo ""
# echo "=== [SECTION B] COMPLETE ==="
# echo "Copy the kubeadm join command printed above and run it on each worker node."
# echo "Also install nfs-common on this node for the NFS provisioner:"
# echo "  sudo apt-get install -y nfs-common"
# echo "Verify nodes with: kubectl get nodes"

# =============================================================================
# SECTION C: WORKER NODES ONLY
# =============================================================================
# Uncomment the lines below and run only on worker1 and worker2

# NFS_SERVER_IP="<EC2-4-PRIVATE-IP>"   # <-- Set this before running
#
# echo "=== [SECTION C] Installing NFS client ==="
# sudo apt-get install -y nfs-common
#
# echo "=== [SECTION C] Mounting NFS share ==="
# sudo mkdir -p /mnt/nfs
# sudo mount ${NFS_SERVER_IP}:/exports/caresync /mnt/nfs
# echo "${NFS_SERVER_IP}:/exports/caresync /mnt/nfs nfs defaults 0 0" | sudo tee -a /etc/fstab
#
# echo "=== [SECTION C] Run the kubeadm join command from master output ==="
# echo "Example:"
# echo "  sudo kubeadm join <MASTER-IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>"
# echo ""
# echo "=== [SECTION C] COMPLETE ==="

#!/bin/bash
# =============================================================================
# ArgoCD + NFS Provisioner + CareSync Full Setup Script
# Run this on the MASTER NODE after the cluster is ready
# Usage: ./argocd-install.sh <NFS-SERVER-IP>
# =============================================================================

set -e

NFS_SERVER_IP="${1}"
if [ -z "$NFS_SERVER_IP" ]; then
  echo "ERROR: NFS server IP is required."
  echo "Usage: ./argocd-install.sh <NFS-SERVER-IP>"
  exit 1
fi

echo ""
echo "================================================================"
echo " CareSync ArgoCD + Infrastructure Setup"
echo " NFS Server IP: ${NFS_SERVER_IP}"
echo "================================================================"
echo ""

# =============================================================================
echo "=== Step 1: Install ArgoCD ==="
# =============================================================================
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "=== Waiting for ArgoCD server to become available (up to 5 minutes) ==="
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s

echo ""
echo "=== Step 2: Retrieve ArgoCD Initial Admin Password ==="
# =============================================================================
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD Admin Password: ${ARGOCD_PASSWORD}"
echo "(Save this password — you will need it to log into the ArgoCD UI)"
echo ""

# =============================================================================
echo "=== Step 3: Install Helm ==="
# =============================================================================
if ! command -v helm &> /dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "Helm is already installed: $(helm version --short)"
fi

# =============================================================================
echo "=== Step 4: Install NFS Subdir External Provisioner ==="
# =============================================================================
helm repo add nfs-subdir-external-provisioner \
  https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

helm upgrade --install nfs-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace kube-system \
  --set nfs.server=${NFS_SERVER_IP} \
  --set nfs.path=/exports/caresync \
  --set storageClass.name=nfs-storage \
  --set storageClass.reclaimPolicy=Retain \
  --set storageClass.accessModes=ReadWriteOnce

echo "=== Waiting for NFS provisioner pod to be ready ==="
kubectl wait --for=condition=available deployment/nfs-provisioner-nfs-subdir-external-provisioner \
  -n kube-system --timeout=120s || true

# =============================================================================
echo "=== Step 5: Install KGateway (Gateway API) CRDs ==="
# =============================================================================
kubectl apply -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/latest/download/standard-install.yaml

# =============================================================================
echo "=== Step 6: Apply Bootstrap Files ==="
# =============================================================================
kubectl apply -f bootstrap/namespace-dev.yaml
kubectl apply -f bootstrap/namespace-prod.yaml
kubectl apply -f bootstrap/storageclass.yaml

echo "Namespaces and StorageClass applied."

# =============================================================================
echo "=== Step 7: Apply ArgoCD Project ==="
# =============================================================================
kubectl apply -f argocd-apps/project.yaml

# =============================================================================
echo "=== Step 8: Deploy DEV Environment (ArgoCD Applications) ==="
# =============================================================================
kubectl apply -f argocd-apps/dev/

echo ""
echo "================================================================"
echo " Setup Complete!"
echo "================================================================"
echo ""
echo "ArgoCD is now syncing all dev services. Watch progress with:"
echo "  kubectl get pods -n caresync-dev -w"
echo "  kubectl get applications -n argocd"
echo ""
echo "Access the ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Then open: https://localhost:8080"
echo "  Username : admin"
echo "  Password : ${ARGOCD_PASSWORD}"
echo ""
echo "To deploy PROD environment when ready:"
echo "  kubectl apply -f argocd-apps/prod/"
echo ""

# CareSync ArgoCD Manifests

GitOps repository for the **CareSync Appointment Booking Platform** — a microservices application deployed to Kubernetes using Helm charts and managed by ArgoCD.

This repository follows a **two-branch GitOps strategy**: the `dev` branch drives the `caresync-dev` namespace and the `production` branch drives the `caresync-prod` namespace. ArgoCD watches both branches and automatically syncs any change to the cluster.

---

## Repository Structure

```
argoCD-manifests/
├── caresync-helm/                       ← Unified Helm chart (all services + infra)
│   ├── Chart.yaml
│   ├── values.yaml                      ← Base defaults (overridden per environment)
│   ├── values-dev.yaml                  ← Dev environment overrides
│   ├── values-prod.yaml                 ← Prod environment overrides
│   └── templates/
│       ├── _helpers.tpl
│       ├── configmap.yaml               ← SERVICE_URLs + MONGO_URIs per env
│       ├── secrets.yaml                 ← JWT secret (create: true/false)
│       ├── deployments.yaml             ← 4 microservice Deployments
│       ├── rollout.yaml                 ← Frontend BlueGreen Rollout (Argo Rollouts)
│       ├── statefulsets.yaml            ← 4 MongoDB StatefulSets + headless Services
│       ├── services.yaml                ← ClusterIP Services for all microservices
│       ├── storage.yaml                 ← PVCs (dynamic NFS, ReadWriteOnce)
│       ├── gateway.yaml                 ← KGateway + NodePort Service + HTTPRoutes
│       ├── hpa.yaml                     ← HorizontalPodAutoscalers (all services)
│       ├── rbac.yaml                    ← ServiceAccounts, Roles, RoleBindings
│       └── network-policies.yaml        ← NetworkPolicies (default-deny + allow rules)
├── argocd/
│   ├── project.yaml                     ← ArgoCD AppProject (caresync)
│   ├── app-dev.yaml                     ← ArgoCD Application → caresync-dev
│   └── app-prod.yaml                    ← ArgoCD Application → caresync-prod
├── bootstrap/
│   ├── namespace-dev.yaml               ← caresync-dev namespace
│   └── namespace-prod.yaml              ← caresync-prod namespace
├── setup/
│   ├── nfs-setup.sh                     ← NFS server setup (run on EC2-4)
│   ├── haproxy.cfg                      ← HAProxy config (TCP round-robin to :30080)
│   ├── cluster-setup.sh                 ← kubeadm + Weave Net setup (all nodes)
│   └── argocd-install.sh                ← Full bootstrap script (run on master)
└── README.md
```

---

## Architecture

```
Internet (HTTP :80)
    │
    ▼
EC2-4: HAProxy (round-robin)
    │
    ├──► EC2-2: Worker Node 1 :30080
    └──► EC2-3: Worker Node 2 :30080
              │
              ▼
         KGateway (Envoy) Service (NodePort :30080)
              │
              ▼
         HTTPRoutes
         ├── /api/auth         → auth-service:4001
         ├── /api/patients     → patient-service:4002
         ├── /api/doctors      → doctor-service:4003
         ├── /api/appointments → appointment-service:4004
         └── /                 → frontend:3000
              │
              ▼
    ClusterIP Services (per microservice)
              │
              ▼
    Application Pods (Deployments)
              │
              ▼
    MongoDB StatefulSets (one per service)
              │
              ▼
    NFS PersistentVolumes (/exports/caresync on EC2-4)
```

---

## Infrastructure

| Instance | Role                  | Notes                        |
|----------|-----------------------|------------------------------|
| EC2-1    | Kubernetes Master     | API server, etcd, scheduler  |
| EC2-2    | Kubernetes Worker 1   | Runs pods, exposes :30080    |
| EC2-3    | Kubernetes Worker 2   | Runs pods, exposes :30080    |
| EC2-4    | HAProxy + NFS Server  | Port 80 → NodePort, NFS storage |

---

## Services and Ports

| Service             | Port | MongoDB Instance    | Database    |
|---------------------|------|---------------------|-------------|
| auth-service        | 4001 | auth-mongodb        | auth        |
| patient-service     | 4002 | patient-mongodb     | patient     |
| doctor-service      | 4003 | doctor-mongodb      | doctor      |
| appointment-service | 4004 | appointment-mongodb | appointment |
| frontend            | 3000 | none                | none        |

All backend services are type `ClusterIP`. MongoDB instances are headless `StatefulSets` with NFS-backed PVCs.

---

## Branch Strategy

| Branch       | Image Tag Format | Target Namespace | Trigger         |
|--------------|-----------------|------------------|-----------------|
| `dev`        | `dev-<sha>`     | `caresync-dev`   | Push to dev     |
| `production` | `v0.0.x`        | `caresync-prod`  | Manual approval |

CI/CD pipelines update `values.yaml` image tags automatically. ArgoCD detects the change and reconciles the cluster state.

---

## Prerequisites Checklist

Before running any setup commands, verify:

- [ ] 4 EC2 instances running Ubuntu 22.04 in the same VPC
- [ ] Security groups configured:
  - EC2-4 HAProxy: port **80** inbound from internet
  - EC2-4 NFS: port **2049** inbound from worker nodes
  - Master + Workers: port **6443** (API server)
  - Master + Workers: port **10250** (kubelet)
  - Workers: port **30080** (NodePort)
  - All nodes: all traffic between each other (same VPC)
- [ ] Docker images pushed to DockerHub as `nandana2002/caresync-*`
- [ ] SSH access to all 4 instances

---

## Complete Setup Guide

### PHASE 1: EC2-4 Setup (HAProxy + NFS)

SSH into EC2-4 and run:

```bash
# Clone the repo first
git clone https://github.com/caresync-org/argoCD-manifests
cd argoCD-manifests

# Set up NFS server
chmod +x setup/nfs-setup.sh
bash setup/nfs-setup.sh

# Verify NFS is running
sudo systemctl status nfs-kernel-server
showmount -e localhost
```

Install and configure HAProxy:

```bash
sudo apt-get install -y haproxy

# Edit haproxy.cfg — replace placeholder IPs with real worker node private IPs
# WORKER1-PRIVATE-IP → e.g. 10.0.1.101
# WORKER2-PRIVATE-IP → e.g. 10.0.1.102
nano setup/haproxy.cfg

sudo cp setup/haproxy.cfg /etc/haproxy/haproxy.cfg
sudo haproxy -c -f /etc/haproxy/haproxy.cfg    # validate config
sudo systemctl restart haproxy
sudo systemctl enable haproxy
```

---

### PHASE 2: Kubernetes Cluster Setup

The `setup/cluster-setup.sh` script has three clearly marked sections.

**Run SECTION A on ALL THREE nodes (master + 2 workers):**

```bash
# Copy and run the SECTION A commands from setup/cluster-setup.sh
# These install containerd, kubeadm, kubelet, kubectl
```

**Run SECTION B on MASTER ONLY:**

```bash
# Uncomment and run the SECTION B commands from setup/cluster-setup.sh
# This runs kubeadm init, sets up kubectl config, installs Flannel CNI
# SAVE the kubeadm join command printed at the end
```

**Run SECTION C on WORKER NODES ONLY:**

```bash
# Uncomment and run the SECTION C commands from setup/cluster-setup.sh
# Set NFS_SERVER_IP to EC2-4 private IP before running
# Then run the kubeadm join command from master output
```

**Verify cluster is ready on master:**

```bash
kubectl get nodes
# Expected:
# NAME      STATUS   ROLES           AGE
# master    Ready    control-plane   Xm
# worker1   Ready    <none>          Xm
# worker2   Ready    <none>          Xm
```

---

### PHASE 3: Push Docker Images to DockerHub

Run on your local machine:

```bash
docker login -u nandana2002

cd auth-service
docker build -t nandana2002/caresync-auth:v1.0 .
docker push nandana2002/caresync-auth:v1.0

cd ../patient-service
docker build -t nandana2002/caresync-patient:v1.0 .
docker push nandana2002/caresync-patient:v1.0

cd ../doctor-service
docker build -t nandana2002/caresync-doctor:v1.0 .
docker push nandana2002/caresync-doctor:v1.0

cd ../appointment-service
docker build -t nandana2002/caresync-appointment:v1.0 .
docker push nandana2002/caresync-appointment:v1.0

cd ../frontend
docker build -t nandana2002/caresync-frontend:v1.0 .
docker push nandana2002/caresync-frontend:v1.0
```

---

### PHASE 4: Update values.yaml with Real Image Tags & Secrets

```bash
# In the argoCD-manifests repo, on the dev branch:

# 1. Edit values.yaml and set all image tags:
#   auth.image.tag: "v1.0"
#   patient.image.tag: "v1.0"
#   doctor.image.tag: "v1.0"
#   appointment.image.tag: "v1.0"
#   frontend.image.tag: "v1.0"

# 2. Add your JWT Secret to values-dev.yaml (for dev ONLY)
#   secrets:
#     create: true
#     jwtSecret: "caresync_jwt_dev_secret_2024"

git add values.yaml caresync-helm/values-dev.yaml
git commit -m "chore: set initial image tags and jwt secret"
git push origin dev
```

---

### PHASE 5: Install ArgoCD and Deploy

SSH into the master node:

```bash
git clone https://github.com/caresync-org/argoCD-manifests
cd argoCD-manifests
git checkout dev

chmod +x setup/argocd-install.sh
./setup/argocd-install.sh <EC2-4-PRIVATE-IP>
```

---

## Verification Commands (Run in This Exact Order)

### Check 1: Cluster Health
```bash
kubectl get nodes
# All nodes must show STATUS = Ready
```

### Check 2: Namespaces
```bash
kubectl get namespaces
# Must see: caresync-dev, caresync-prod, argocd
```

### Check 3: StorageClass
```bash
kubectl get storageclass
# Must see: nfs-storage  PROVISIONER: k8s-sigs.io/nfs-subdir-external-provisioner
```

### Check 4: NFS Provisioner
```bash
kubectl get pods -n kube-system | grep nfs
# Must show 1 pod Running
```

### Check 5: ArgoCD Status
```bash
kubectl get pods -n argocd
# All pods must be Running
```

### Check 6: ArgoCD Applications
```bash
kubectl get applications -n argocd
# All apps: SYNC STATUS = Synced, HEALTH STATUS = Healthy
```

### Check 7: All Pods Running
```bash
kubectl get pods -n caresync-dev
# Expected pods:
# auth-service-xxxxxxxxx           1/1   Running
# patient-service-xxxxxxxxx        1/1   Running
# doctor-service-xxxxxxxxx         1/1   Running
# appointment-service-xxxxxxxxx    1/1   Running
# frontend-xxxxxxxxx               1/1   Running
# auth-mongodb-0                   1/1   Running
# patient-mongodb-0                1/1   Running
# doctor-mongodb-0                 1/1   Running
# appointment-mongodb-0            1/1   Running
```

### Check 8: Services
```bash
kubectl get svc -n caresync-dev
# Backend services: TYPE = ClusterIP
# caresync-gateway-nodeport: TYPE = NodePort, PORT = 30080
```

### Check 9: PVCs Bound
```bash
kubectl get pvc -n caresync-dev
# All 4 MongoDB PVCs must show STATUS = Bound
```

### Check 10: StatefulSets Ready
```bash
kubectl get statefulsets -n caresync-dev
# All must show READY = 1/1
```

### Check 11: Gateway Resources
```bash
kubectl get gateway -n caresync-dev
kubectl get httproute -n caresync-dev
kubectl get svc caresync-gateway-nodeport -n caresync-dev
```

### Check 12: Test Endpoints via NodePort
```bash
# Replace WORKER-IP with any worker node public IP
curl http://<WORKER-IP>:30080/api/auth/health
# Expected: {"status":"ok","service":"auth-service"}

curl http://<WORKER-IP>:30080/api/patients/health
# Expected: {"status":"ok","service":"patient-service"}

curl http://<WORKER-IP>:30080/api/doctors/health
# Expected: {"status":"ok","service":"doctor-service"}

curl http://<WORKER-IP>:30080/api/appointments/health
# Expected: {"status":"ok","service":"appointment-service"}

curl http://<WORKER-IP>:30080/
# Expected: HTML content of React frontend
```

### Check 13: Test Through HAProxy
```bash
# Replace HAPROXY-IP with EC2-4 public IP
curl http://<HAPROXY-IP>/api/auth/health
curl http://<HAPROXY-IP>/api/patients/health
curl http://<HAPROXY-IP>/api/doctors/health
curl http://<HAPROXY-IP>/api/appointments/health
curl http://<HAPROXY-IP>/
```

### Check 14: ArgoCD UI Access
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open browser: https://localhost:8080
# Username: admin
# Password:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

---

## Troubleshooting

### Pod shows ImagePullBackOff
```bash
kubectl describe pod <pod-name> -n caresync-dev
# Fix: Verify image exists on DockerHub
docker pull nandana2002/caresync-auth:v1.0
```

### Pod shows CrashLoopBackOff
```bash
kubectl logs <pod-name> -n caresync-dev
kubectl logs <pod-name> -n caresync-dev --previous
# Fix: Usually MongoDB not ready yet — wait 2 minutes and check again
```

### PVC stays Pending
```bash
kubectl describe pvc -n caresync-dev
kubectl get pods -n kube-system | grep nfs
# Fix: NFS provisioner not running
# On EC2-4: sudo systemctl status nfs-kernel-server
```

### MongoDB pod not starting
```bash
kubectl logs auth-mongodb-0 -n caresync-dev
# Fix: Check NFS mount on worker nodes
mount | grep nfs
```

### Gateway not routing traffic
```bash
kubectl describe httproute -n caresync-dev
kubectl describe gateway -n caresync-dev
kubectl get svc -n caresync-dev | grep nodeport
```

### ArgoCD app shows OutOfSync
```bash
kubectl get application auth-service-dev -n argocd -o yaml
# Fix: Check values.yaml image tags are valid
# Check targetRevision branch exists in repo
```

### Check specific service logs
```bash
kubectl logs -n caresync-dev deployment/auth-service
kubectl logs -n caresync-dev deployment/patient-service
kubectl logs -n caresync-dev deployment/doctor-service
kubectl logs -n caresync-dev deployment/appointment-service
kubectl logs -n caresync-dev deployment/frontend
kubectl logs -n caresync-dev statefulset/auth-mongodb
```

---

## Production Deployment

After dev environment is verified working:

```bash
# Step 1: Create production branch in argoCD-manifests
git checkout -b production
git push origin production

# Step 2: Edit values.yaml in production branch
# Change these fields ONLY:
#   global.namespace: caresync-prod
#   mongodb.persistence.size: 5Gi
#   auth.env.NODE_ENV: production
#   patient.env.NODE_ENV: production
#   doctor.env.NODE_ENV: production
#   appointment.env.NODE_ENV: production

git add values.yaml
git commit -m "chore: production environment values"
git push origin production

# Step 3: Deploy prod ArgoCD apps (from dev branch)
git checkout dev
kubectl apply -f argocd-apps/prod/

# Step 4: Verify prod namespace
kubectl get pods -n caresync-prod
```

---

## CI/CD Flow

```
Developer push to dev branch (any microservice repo)
    │
    ├── Job 1: SonarQube code quality scan
    ├── Job 2: Snyk dependency security scan
    ├── Job 3: Docker build + Trivy image scan + push to DockerHub
    └── Job 5: Update values.yaml image tag in argoCD-manifests (dev branch)
                    │
                    ▼
             ArgoCD detects change → deploys to caresync-dev

Developer push to production branch
    │
    ├── Jobs 1, 2, 3 run (same as dev)
    ├── Job 4: Manual approval gate required
    └── Job 5: Update values.yaml image tag in argoCD-manifests (production branch)
                    │
                    ▼
             ArgoCD detects change → deploys to caresync-prod
```

---

## DockerHub Images

| Image                              | Service             |
|------------------------------------|---------------------|
| `nandana2002/caresync-auth`        | auth-service        |
| `nandana2002/caresync-patient`     | patient-service     |
| `nandana2002/caresync-doctor`      | doctor-service      |
| `nandana2002/caresync-appointment` | appointment-service |
| `nandana2002/caresync-frontend`    | frontend            |

---

## Troubleshooting

### MongoDB pods stuck at `0/1 Running` — probes timing out

**Symptom:** MongoDB pods restart every ~60s. Events show:
`command timed out: "mongosh --eval db.adminCommand('ping')" timed out after 1s`

**Root cause:** `timeoutSeconds` was not set → defaults to `1s`. `mongosh` takes 2–4s to start
on constrained CPU (200m request) over NFS I/O. The liveness probe killed MongoDB after 3 failures.
`Exit Code: 0` confirms a clean kill by the probe, not a crash.

**Fix (applied in `statefulsets.yaml`):**
```yaml
livenessProbe:
  exec:
    command: [mongosh, --quiet, --eval, "db.adminCommand('ping')"]
  timeoutSeconds: 10    # ← key fix; was unset (defaulted to 1s)
  failureThreshold: 3
readinessProbe:
  exec:
    command: [mongosh, --quiet, --eval, "db.adminCommand('ping')"]
  timeoutSeconds: 10
  failureThreshold: 3
```

---

### Service pods stuck at `Init:0/1`

**Symptom:** `caresync-*-service` pods show `Init:0/1` indefinitely.

**Root cause:** Init container runs `nc -z caresync-*-mongodb 27017`. The headless Service
only routes DNS to **Ready** pods. Since MongoDB readiness was failing (see above), `nc` could
never connect → init container loops forever.

**Fix:** Fixing the MongoDB probe timeout above unblocks init containers automatically.

---

### ArgoCD shows `caresync-secrets` as `OutOfSync / Missing`

**Symptom:** ArgoCD reports the Secret as OutOfSync. All services crash — `JWT_SECRET` env var is empty.

**Cause:** `values-dev.yaml` had `jwtSecret: ""` → Helm created a Secret with an empty value.

**Fix — Option A (dev, simple):** Set the value in `values-dev.yaml`:
```yaml
secrets:
  create: true
  jwtSecret: "caresync_jwt_dev_secret_2024"
```

**Fix — Option B (production, secure):** Create the secret manually and disable Helm management:
```bash
kubectl create secret generic caresync-secrets \
  --from-literal=JWT_SECRET="<your-real-secret>" \
  --namespace caresync-dev \
  --dry-run=client -o yaml | kubectl apply -f -
```
Then set `secrets.create: false` in `values-dev.yaml`.

> **Never commit real production secrets to Git.** Use Sealed Secrets or External Secrets Operator for production.

---

### HAProxy returns 503 for all requests

**Symptom:** All HTTP requests through EC2-4 return 503.

**Root cause:** `haproxy.cfg` used `option httpchk GET /health`. The kgateway Envoy proxy has no
`/health` endpoint on port 30080 → HAProxy marks both workers as DOWN → all traffic dropped.

**Fix (applied in `setup/haproxy.cfg`):** Changed to `option tcp-check`.
After copying the updated config to EC2-4:
```bash
sudo cp setup/haproxy.cfg /etc/haproxy/haproxy.cfg
sudo haproxy -c -f /etc/haproxy/haproxy.cfg   # validate
sudo systemctl restart haproxy
```

---

### ArgoCD `applicationset-controller` in CrashLoopBackOff

**Symptom:** `argocd-applicationset-controller` pod shows `CrashLoopBackOff`. All other ArgoCD pods are fine.

**Impact:** None for this project — ApplicationSets are not used here. All apps are standalone
`Application` CRDs applied directly. You can safely ignore this crash.

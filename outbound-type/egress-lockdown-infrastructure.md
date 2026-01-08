# Create AKS Cluster on Egress Lockdown Infrastructure

This guide shows how to create an AKS cluster using Azure CLI on the egress lockdown infrastructure with Azure Firewall.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Appropriate Azure subscription permissions
- Egress lockdown infrastructure already deployed - See [Egress Lockdown README](../egress-lockdown/README.md)

## Deployment Steps

### 1. Get Infrastructure Outputs

Retrieve the subnet ID and firewall private IP:

```bash
RESOURCE_GROUP="rg-aks-egress-lockdown-dev"
SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RESOURCE_GROUP \
  --vnet-name vnet-aks-egress-dev \
  --name aks-subnet \
  --query id -o tsv)

FIREWALL_IP=$(az network firewall show \
  --resource-group $RESOURCE_GROUP \
  --name afw-aks-dev \
  --query ipConfigurations[0].privateIPAddress -o tsv)
```

### 2. Create AKS Cluster with Outbound Type UDR

Create an AKS cluster that uses the User Defined Route (UDR) for egress traffic:

```bash
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name aks-egress-cluster \
  --vnet-subnet-id $SUBNET_ID \
  --network-plugin azure \
  --outbound-type userDefinedRouting \
  --service-cidr 172.16.0.0/16 \
  --dns-service-ip 172.16.0.10 \
  --node-vm-size Standard_DS4_v2 \
  --generate-ssh-keys
```

This creates an AKS cluster with:
- Default node count (3)
- VM size: Standard_DS4_v2
- System-assigned managed identity
- Default Kubernetes version
- Azure CNI networking
- User Defined Routing for egress traffic (routes through Azure Firewall)
- Automatically generated SSH keys

### 3. Connect to Jump Server

Since this is a private cluster setup, you'll need to use the jump server to access kubectl:

```bash
# Get the jump server public IP
JUMP_SERVER_IP=$(az vm show \
  --resource-group $RESOURCE_GROUP \
  --name vm-jump-server \
  --show-details \
  --query publicIps -o tsv)

# SSH to jump server
ssh -i ~/.ssh/id_rsa_aks_jump azureuser@$JUMP_SERVER_IP
```

### 4. Install Tools on Jump Server

Once connected to the jump server, install required tools:

```bash
# Install kubectl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl

# Install Helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install -y helm

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### 5. Get Cluster Credentials on Jump Server

Login to Azure using the jump server's managed identity and get AKS credentials:

```bash
# Login to Azure using managed identity
az login --identity

# Get AKS credentials
az aks get-credentials \
  --resource-group rg-aks-egress-lockdown-dev \
  --name aks-egress-cluster
```

### 6. Verify Cluster

```bash
kubectl get nodes
kubectl get pods -A
```

## Clean Up

### Delete AKS Cluster Only

```bash
az aks delete \
  --resource-group $RESOURCE_GROUP \
  --name aks-egress-cluster \
  --yes --no-wait
```


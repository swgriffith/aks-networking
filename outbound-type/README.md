# Create AKS Cluster with Azure CLI

This guide shows how to create an AKS cluster using Azure CLI with default options on both the basic infrastructure and egress lockdown infrastructure.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Appropriate Azure subscription permissions
- Infrastructure already deployed:
  - For basic infrastructure: See [Basic Infrastructure README](../basic/README.md)
  - For egress lockdown infrastructure: See [Egress Lockdown README](../egress-lockdown/README.md)

## Option 1: Basic Infrastructure

Create an AKS cluster using the basic infrastructure with all default options.

> **Note**: Ensure you've deployed the basic infrastructure first. See [Basic Infrastructure README](../basic/README.md) for deployment instructions.

### 1. Get Infrastructure Outputs

Retrieve the subnet ID from the deployment:

```bash
RESOURCE_GROUP="rg-aks-networking-dev"
SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RESOURCE_GROUP \
  --vnet-name vnet-aks-dev \
  --name aks-subnet \
  --query id -o tsv)
```

### 3. Create AKS Cluster with Default Options

Create an AKS cluster with all default options:

```bash
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name aks-basic-cluster \
  --vnet-subnet-id $SUBNET_ID \
  --network-plugin azure \
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
- Automatically generated SSH keys

### 4. Get Cluster Credentials

```bash
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name aks-basic-cluster
```

### 5. Verify Cluster

```bash
kubectl get nodes
kubectl get pods -A
```

## Option 2: Egress Lockdown Infrastructure

Create an AKS cluster using the egress lockdown infrastructure with Azure Firewall.

> **Note**: Ensure you've deployed the egress lockdown infrastructure first. See [Egress Lockdown README](../egress-lockdown/README.md) for deployment instructions.

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

### 3. Create AKS Cluster with Outbound Type UDR

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

### 4. Connect to Jump Server

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

### 3. Get Cluster Credentials on Jump Server

Once connected to the jump server, install tools and get the cluster credentials:

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

# Login to Azure using managed identity
az login --identity

# Get AKS credentials
az aks get-credentials \
  --resource-group rg-aks-egress-lockdown-dev \
  --name aks-egress-cluster
```
4
### 5. Verify Cluster

```bash
kubectl get nodes
kubectl get pods -A
```

## Additional Configuration Options

### Customize Node Count

```bash
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name aks-cluster \
  --vnet-subnet-id $SUBNET_ID \
  --network-plugin azure \
  --service-cidr 172.16.0.0/16 \
  --dns-service-ip 172.16.0.10 \
  --node-count 5 \
  --generate-ssh-keys
```

### Customize VM Size

```bash
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name aks-cluster \
  --vnet-subnet-id $SUBNET_ID \
  --network-plugin azure \
  --service-cidr 172.16.0.0/16 \
  --dns-service-ip 172.16.0.10 \
  --node-vm-size Standard_D4s_v3 \
  --generate-ssh-keys
```

### Specify Kubernetes Version

```bash
# List available versions
az aks get-versions --location eastus --output table

# Create with specific version
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name aks-cluster \
  --vnet-subnet-id $SUBNET_ID \
  --network-plugin azure \
  --service-cidr 172.16.0.0/16 \
  --dns-service-ip 172.16.0.10 \
  --kubernetes-version 1.29.0 \
  --generate-ssh-keys
```

## Troubleshooting

### Cluster creation fails with network errors

Ensure:
- The subnet has enough available IP addresses
- The route table is properly attached to the subnet (egress lockdown scenario)
- Firewall rules allow necessary AKS egress traffic (egress lockdown scenario)

### Cannot connect to cluster

For basic infrastructure:
- Verify you have the credentials: `az aks get-credentials`
- Check your kubeconfig: `kubectl config current-context`

For egress lockdown infrastructure:
- Use the jump server to access the cluster
- Verify the jump server can reach the AKS API server

### Nodes not ready

```bash
# Check node status
kubectl get nodes

# Describe nodes for more details
kubectl describe nodes

# Check system pods
kubectl get pods -n kube-system
```

## Clean Up

### Delete AKS Cluster Only

```bash
az aks delete \
  --resource-group $RESOURCE_GROUP \
  --name aks-cluster \
  --yes --no-wait
```

### Delete Everything Including Infrastructure

Basic infrastructure:
```bash
az group delete --name rg-aks-networking-dev --yes --no-wait
```

Egress lockdown infrastructure:
```bash
az group delete --name rg-aks-egress-lockdown-dev --yes --no-wait
```

## Cost Considerations

AKS cluster costs depend on:
- **Compute nodes**: Charged at standard VM pricing rates
- **Standard_DS2_v2** (default): ~$96.36/month per node
- **Standard_D4s_v3**: ~$175.20/month per node
- **Load Balancer**: Standard Load Balancer charges apply
- **Public IPs**: Charged for any public IPs used
- **Azure Firewall** (egress lockdown only): ~$1.25/hour + data processing charges

> **Note**: 3-node cluster with default settings costs approximately $290/month for compute + additional costs for load balancer and data transfer.

## Next Steps

After deploying your AKS cluster:
1. Deploy sample applications
2. Configure ingress controllers
3. Set up monitoring with Azure Monitor
4. Configure Azure Policy for governance
5. Implement pod security policies
6. Set up CI/CD pipelines

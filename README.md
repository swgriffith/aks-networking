# AKS Networking Examples

This repository contains sample deployments demonstrating various Azure Kubernetes Service (AKS) networking features and configurations. Each example includes infrastructure-as-code templates using Bicep and step-by-step deployment guides.

## Infrastructure Setup Options

Before deploying AKS clusters, you need to set up the underlying network infrastructure. Choose one of the following options:

### Option 1: Basic Infrastructure
A simple network setup with a virtual network and subnet for AKS nodes. Uses Azure's default routing for internet egress.

- **Location**: [infra/basic/](infra/basic/)
- **Components**: Resource Group, VNet, AKS Subnet
- **Documentation**: [Basic Infrastructure README](infra/basic/README.md)

### Option 2: Egress Lockdown Infrastructure
A secure network setup with Azure Firewall for controlled egress traffic and a jump server for secure access.

- **Location**: [infra/egress-lockdown/](infra/egress-lockdown/)
- **Components**: Resource Group, VNet, AKS Subnet, Azure Firewall, Route Table, Jump Server
- **Documentation**: [Egress Lockdown README](infra/egress-lockdown/README.md)

## AKS Deployment Examples

| Example | Description | Infrastructure | Documentation |
|---------|-------------|----------------|---------------|
| Basic AKS Cluster | Deploy an AKS cluster with Azure CNI networking using Azure CLI with default options | Basic or Egress Lockdown | [Guide](/default-aks-cluster/README.md) |

## Prerequisites

- **Azure CLI**: [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- **Bicep CLI**: Included with Azure CLI 2.20.0 and later
- **Azure Subscription**: With appropriate permissions to create resources
- **kubectl**: For managing Kubernetes clusters
- **SSH Keys**: For secure access to jump servers (egress lockdown scenarios)

## Getting Started

1. **Choose an infrastructure setup** based on your requirements (basic or egress lockdown)
2. **Deploy the infrastructure** following the respective README guide
3. **Select an AKS deployment example** from the table above
4. **Follow the deployment guide** to create your AKS cluster
5. **Explore and experiment** with different networking configurations

## Repository Structure

```
aks-networking/
├── README.md                           # This file
├── infra/
│   ├── basic/                          # Basic infrastructure
│   │   ├── main.bicep
│   │   ├── main.bicepparam
│   │   └── README.md
│   ├── egress-lockdown/                # Egress lockdown infrastructure
│   │   ├── main.bicep
│   │   ├── main.bicepparam
│   │   └── README.md
│   └── default-aks-cluster/            # Basic AKS cluster deployment
│       └── README.md
```

## Contributing

Examples and improvements are welcome! Feel free to submit issues or pull requests.

## Resources

- [AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [AKS Networking Concepts](https://docs.microsoft.com/en-us/azure/aks/concepts-network)
- [Azure CNI Networking](https://docs.microsoft.com/en-us/azure/aks/configure-azure-cni)
- [Azure Firewall with AKS](https://docs.microsoft.com/en-us/azure/aks/limit-egress-traffic)
- [Azure Verified Modules](https://aka.ms/avm)

# k8s-hosts-controller

A Kubernetes controller that watches Ingress resources and automatically syncs their hostnames and LoadBalancer IPs to `/etc/hosts`. This enables local development environments to access Kubernetes services via hostnames without manual `/etc/hosts` management or port-forwards.

## Problem

At Tyk, while we are running resilience tests with Toxiproxy in local Kubernetes environments (kind), using `kubectl port-forward` causes issues:

1. When Toxiproxy disables a proxy, the port-forward process terminates
2. When the proxy is re-enabled, port-forward remains dead
3. Tests fail with "Connection refused" errors

This controller eliminates port-forwards by watching Ingress resources in specified namespaces, extracting hostnames and IPs from Ingress and updating the `/etc/hosts` with the mappings to allow local machines to access LB services via DNS.

> The controller requires `sudo` access in order to writing to `/etc/hosts`.

## Usage

### Build

```bash
go build -o k8s-hosts-controller .
```

### Run

Watch specific namespaces:
```bash
sudo ./k8s-hosts-controller --namespaces tyk,tyk-dp-1,tyk-dp-2
```

Watch all namespaces:
```bash
sudo ./k8s-hosts-controller --all-namespaces
```

Remove all managed entries from `/etc/hosts` (no controller, just a single shot):
```bash
sudo ./k8s-hosts-controller --cleanup
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--namespaces` | Comma-separated namespaces to watch | (required unless `--all-namespaces`) |
| `--all-namespaces` | Watch all namespaces | `false` |
| `--hosts-file` | Path to hosts file | `/etc/hosts` |
| `--marker` | Marker for managed entries | `TYK-K8S-HOSTS` |
| `--cleanup` | Remove all managed entries and exit | `false` |
| `--verbose` | Enable verbose logging | `false` |

### Hosts File Format

Entries are managed within marked blocks:
```
# existing entries...

#### BEGIN TYK-K8S-HOSTS ####
# Ingress: tyk/dashboard-ingress
172.18.0.100	chart-dash.local
# Ingress: tyk/gateway-ingress
172.18.0.100	chart-gw.local
#### END TYK-K8S-HOSTS ####
```

## Troubleshooting

### No LoadBalancer IP assigned

Ensure `cloud-provider-kind` is running:
```bash
# Check if it's running
docker ps | grep cloud-provider-kind

# If not, the create-cluster.sh script from `tyk-pro` repository starts it automatically
```

### Permission denied writing to /etc/hosts

Run the controller with sudo:
```bash
sudo ./k8s-hosts-controller --namespaces tyk
```

# Install Metal Lb In the Cluster

## Metal

```bash
helm install metallb metallb/metallb -n metallb-system
#kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
kubectl apply -f resources.yaml
```


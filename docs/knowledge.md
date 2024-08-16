# Knowledge Base


## Helm

- Normally you do `helm upgrade --install ...` to deploy, providing custom values via cli or file. Then you can later upgrade or delete via helm.
- `helm list -A` shows what you have
- `helm template .... > manifest.yaml`: Then you create "the yaml", for `kubectl apply` - but:
  - You can't use helm for upgrades
  - The helm template command will **not** output a **Namespace** resource and ignores the `--create-namespace` flag. You must ensure the namespace you are deploying the generated YAML to exists.
- `helm delete` and `helm uninstall` are the same. 
   In Helm 2, the command to remove a release was `helm delete`. In Helm 3, this command was renamed to `helm uninstall` for clarity, but `helm delete` was kept as an alias for backward compatibility. Both commands will remove a Helm release and its associated resources from your Kubernetes cluster. If you want to keep the release history, you can use the `--keep-history` flag.


## CertManager

Issuer vs ClusterIssuer:

From [here](https://cert-manager.io/docs/concepts/issuer/):

If you want to create a single Issuer that can be consumed in multiple namespaces, you should consider creating a ClusterIssuer resource. This is almost identical to the Issuer resource, however is non-namespaced so it can be used to issue Certificates across all namespaces.

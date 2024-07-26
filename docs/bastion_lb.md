# Using bastion node as LB

Couldn't we save the additional 8euro for the service loadbalancer, which does actually only TCP forward 80 and 443 into the cluster - by  using the bastion node?

Let's try add it to the cluster. See [here](./media/bastion_proxy.txt) regarding why.


For now, we break to original plan to have bastion empty and add it to the cluster (Pointer to self: https://dgraph.io/blog/post/building-a-kubernetes-ingress-controller-with-caddy/ (maybe some day I make my own))

## Adding bastion to the cluster

This does it and will work if `ssh broot and ssh m1` work, and enp7s0 is in 10 network and eth0 in the internet:

```bash
function bastion_into_cluster {
        echo '🧧This function requires ssh configs for: broot (root@bastion) and m1 (root@master)!'
        scp m1:/var/lib/rancher/k3s/server/node-token . || return
        token=$(cat node-token)
        rm node-token
        ssh broot ifconfig | grep -A 2 eth0 | grep inet | xargs | cut -d ' ' -f 2 >ippub || return
        ip=$(cat ippub)
        rm ippub
        ver="$(kubectl version | grep Server | cut -d ':' -f2 | xargs)" || return
        echo 'k3s-agent-uninstall.sh; curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="'$ver'" K3S_URL=https://10.0.0.4:6443 K3S_TOKEN="'$token'" INSTALL_K3S_EXEC="agent --node-name=bastion --kubelet-arg=cloud-provider=external --node-ip=10.0.0.2 --node-external-ip='$ip' --flannel-iface=enp7s0" sh -' >inst
        chmod +x inst
        scp inst broot:
        rm inst
        ssh broot ./inst || echo '🚨Failed to install agent!'
}
```

Discussion:

1. Get the token from any master node (/var/lib/rancher/k3s/server/node-token)

2. Get the k3s version, export it as `ver`

```
k version | grep Server                                                                                                      !?
Server Version: v1.30.2+k3s2
```

2. On bastion, as root, after uninstalling any existing membership:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$ver" K3S_URL=https://10.0.0.4:6443 K3S_TOKEN="$t" INSTALL_K3S_EXEC="agent --node-name=bastion --kubelet-arg=cloud-provider=external --node-ip=10.0.0.2 --node-external-ip=95.217.1.185 --flannel-iface=enp7s0" sh -
```

Note: I did get those arguments by scaling up to a "big" node, so that I had an agent and checked /etc/systemd/system/k3s-agent.service

Note: The autoscaler will complain that it can't handle bastion but simply ignore those logs.


## Install

```bash
  …/gitops/docs/traefik❯ cat values.yaml
deployment:
  tolerations:
  - key: "key"
    operator: "Equal"
    value: "value"
    effect: "NoSchedule"
deployment:
  nodeSelector:
    kubernetes.io/hostname: bastion


  …/gitops/docs/traefik❯ helm repo add traefik https://helm.traefik.io/traefik
"traefik" has been added to your repositories

  …/gitops/docs/traefik❯ helm repo update     
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "onechart" chart repository
...Successfully got an update from the "traefik" chart repository
  …/gitops/docs/traefik❯ helm install traefik traefik/traefik -f values.yaml 
NAME: traefik
LAST DEPLOYED: Wed Jul 17 12:57:19 2024
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Traefik Proxy v3.0.4 has been deployed successfully on default namespace !
```

❤️ sweet

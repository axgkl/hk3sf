# Using bastion node as LB

We add it to the cluster:

1. Get the token from any master node (/var/lib/rancher/k3s/server/node-token), export it as `t` on bastion.

2. Get the k3s version, export it as `ver`

```
k version | grep Server                                                                                                      !?
Server Version: v1.30.2+k3s2
```

2. On bastion, as root:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$ver" K3S_URL=https://10.0.0.4:6443 K3S_TOKEN="$t" INSTALL_K3S_EXEC="agent --node-name=bastion --kubelet-arg=cloud-provider=external --node-ip=10.0.0.2 --node-external-ip=95.217.1.185 --flannel-iface=enp7s0" sh -
```

Note: I did get those arguments by scaling up to a "big" node, so that I had an agent and checked /etc/systemd/system/k3s-agent.service




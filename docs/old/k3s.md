# Lets build the k3s cluster



We use [hetzner-k3s](https://github.com/vitobotta/hetzner-k3s)

The default, way better than terraform. 

<details><summary>On fedora</summary></details>
BUT: Did not run on my fedora, so:

- Built the tool from source: https://github.com/vitobotta/hetzner-k3s/issues/309#issuecomment-2080853984
- Moved to /usr/local/bin/hetzner-k3s

</details>


We start from an empty project.

## Private Network

In cloud console UI, create 'ten-0' private network, 10.0.0.0/16

## Bastion Host

The one host with a pub v4 IP (50cents/mo)

### Create it

Using hetzner gui, lowest priced amd server, ubuntu 22, hostname **bastion**.

### Make it a proxy

I know - but I'll find it easier to do it this way:


```ini
[Unit]
Description=Bastion Proxy

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'
ExecStart=/bin/bash -c 'iptables -t nat -A POSTROUTING -s '10.0.0.0/16' -o eth0 -j MASQUERADE'

[Install]
WantedBy=multi-user.target

```

Then `systemctl enable bastion_proxy`

### "Secure" it

- ssh port away from 22 in /etc/ssh/sshd_config
- paswd auth off

```bash
apt update
apt install unattended-upgrades
apt install update-notifier-common
systemctl enable unattended-upgrades
systemctl start unattended-upgrades
apt install fail2ban
cat .ssh/authorized_keys > /tmp/k
adduser admin
su - admin
ssh-keygen
cat /tmp/k > .ssh/authorized_keys
exit
reboot # (systemctl restart sshd was not available)
```

❗ After Jia Tan, (...), ssh vulnerability, even crowdstrike: This is not really secure. [This](https://youtu.be/xhXMnFHwzF0?t=837) is secure, exclusive kernel backdoors.

But well. We'll find time for Talos later.


### Pet it

As user admin:

Install <a href="https://github.com/devops-works/binenv">binenv</a> (just copy and paste the installer script into your shell).

Then (all optional except kubectl): `for i in kubectl kubens kubectx k9s; do binenv install $i; done` 


## K3s Cluster

### Prepare

On bastion

Install [hetzner-k3s](https://github.com/vitobotta/hetzner-k3s)

Not yet in binenv, so:

```bash
wget https://github.com/vitobotta/hetzner-k3s/releases/download/v1.1.5/hetzner-k3s-linux-arm64
chmod +x hetzner-k3s-linux-arm64
sudo mv hetzner-k3s-linux-arm64 /usr/local/bin/hetzner-k3s
mkdir axc3 # arbitrary cluster name
```


### Configure cluster

First create a project space only api token and put it into environ, e.g.: 

    export HCLOUD_TOKEN="NQkec...."

<details><summary>Create config.yaml: </summary>

```yaml
---
cluster_name: axc3
kubeconfig_path: "./kubeconfig"
#k3s_version: v1.29.6+k3s2
k3s_version: v1.30.2+k3s2
public_ssh_key_path: "~/.ssh/id_ed25519.pub"
private_ssh_key_path: "~/.ssh/id_ed25519"
use_ssh_agent: false # set to true if your key has a passphrase or if SSH connections don't work or seem to hang without agent. See https://github.com/vitobotta/hetzner-k3s#limitations
ssh_port: 60001
ssh_allowed_networks:
  - 10.0.0.0/16
  - 95.217.1.185/32
api_allowed_networks:
  - 10.0.0.0/16 # ensure your current IP is included in the range
  - 95.217.1.185/32
private_network_subnet: 10.0.0.0/16 # ensure this doesn't overlap with other networks in the same project
disable_flannel: true # set to true if you want to install a different CNI
schedule_workloads_on_masters: true
cluster_cidr: 10.50.0.0/16 # optional: a custom IPv4/IPv6 network CIDR to use for pod IPs
service_cidr: 10.60.0.0/16 # optional: a custom IPv4/IPv6 network CIDR to use for service IPs. Warning, if you change this, you should also change cluster_dns!
cluster_dns: 10.60.0.10 # optional: IPv4 Cluster IP for coredns service. Needs to be an address from the service_cidr range
enable_public_net_ipv4: false # default is true
enable_public_net_ipv6: true # default is true
# image: rocky-9 # optional: default is ubuntu-22.04
# autoscaling_image: 103908130 # optional, defaults to the `image` setting
# snapshot_os: microos # optional: specified the os type when using a custom snapshot
# cloud_controller_manager_manifest_url: "https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/download/v1.19.0/ccm-networks.yaml"
# csi_driver_manifest_url: "https://raw.githubusercontent.com/hetznercloud/csi-driver/v2.6.0/deploy/kubernetes/hcloud-csi.yml"
# system_upgrade_controller_deployment_manifest_url: "https://github.com/rancher/system-upgrade-controller/releases/download/v0.13.4/system-upgrade-controller.yaml"
# system_upgrade_controller_crd_manifest_url: "https://github.com/rancher/system-upgrade-controller/releases/download/v0.13.4/crd.yaml"
# cluster_autoscaler_manifest_url: "https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/hetzner/examples/cluster-autoscaler-run-on-master.yaml"
datastore:
  mode: etcd # etcd (default) or external
  #external_datastore_endpoint: postgres://....
masters_pool:
  instance_type: cx22
  instance_count: 3
  location: hel1

worker_node_pools:
  - name: small-static
    instance_type: cx32
    instance_count: 0
    location: hel1
    image: debian-11
    # labels:
    #   - key: purpose
    #     value: blah
    # taints:
    #   - key: something
    #     value: value1:NoSchedule

  - name: big-autoscaled
    instance_type: cx42
    location: hel1
    image: debian-11
    autoscaling:
      enabled: true
      min_instances: 0
      max_instances: 10

additional_packages:
 - ifupdown
post_create_commands:
  - printf "started" > status
  - timedatectl set-timezone Europe/Berlin
  - ip route add default via 10.0.0.1
  - ip route add 169.254.0.0/16 via 172.31.1.1
  - mkdir -p /etc/network/interfaces.d
  - echo "auto enp7s0"                                              > /etc/network/interfaces.d/enp7s0
  - echo "iface enp7s0 inet dhcp"                                  >> /etc/network/interfaces.d/enp7s0
  - echo "    post-up ip route add default via 10.0.0.1"           >> /etc/network/interfaces.d/enp7s0
  - echo "    post-up ip route add 169.254.169.254 via 172.31.1.1" >> /etc/network/interfaces.d/enp7s0
  - rm -f                            /etc/resolv.conf
  - echo 'nameserver 185.12.64.1'  > /etc/resolv.conf
  - echo 'nameserver 185.12.64.2' >> /etc/resolv.conf
  - echo 'edns edns0 trust-ad'    >> /etc/resolv.conf
  - echo 'search .' >> /etc/resolv.conf
  - echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINv5SyO4Q/5T4DxHNJNsoPugxygBildbwif0T9ydO9Eg admin@bast' >> /root/.ssh/authorized_keys
  - echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCgeOVWb+48YBsol6boymINTiG9enAlIGN7+raE/z1XVsWax/kBAHx7duVUfEY49y51Ubet8/jZfUAGfxSY6sbnQ2iacjD1kqqdSpEwgYs7MWGfi7XnHscqqMa6oE416VtaH3HodGzIsAjwmSnEpkDZnYQtR/FOyuqRB83z1DtkSpyLRQnCCU1nkU2ASX9egHeRnkOvvql3h12Wn0W6BW4dbAdHfgacHwYNxfPR5r4ziW3xhGi74010jSX4B8GBC/hSV0b5JWqKcf5e9hiYo3X80LCdH8Ar/IF8KEiS8hGfmgN3alC7nshwFNmEMlehUcQdFzPTWgUwzZolAYFuA0av klessinger@fedora30' >> /root/.ssh/authorized_keys
  - echo "root:xhSV0b5JWqKcf5e9hiYo3X80LCdH8A" | chpasswd
  - printf "done" > status



enable_encryption: false
existing_network: ten-0
# kube_api_server_args:
# - arg1
# - ...
# kube_scheduler_args:
# - arg1
# - ...
# kube_controller_manager_args:
# - arg1
# - ...
# kube_cloud_controller_manager_args:
# - arg1
# - ...
# kubelet_args:
# - arg1
# - ...
# kube_proxy_args:
# - arg1
# - ...
#api_server_hostname: k3s1.mydomain.net # optional: DNS for the k8s API LoadBalancer. After the script has run, create a DNS record with the address of the API LoadBalancer.

```
</details>


Discussion:

- Disabled flannel after having had later problems with observability of the cluster, i.e. really required Cilium/Hubble CNI. See [later](./netw.md).
- Manually setting the ssh pub keys I did because via this, the nodes created by the autoscaler (which only applies that cloud init) had my keys
- More details about my config here: https://github.com/vitobotta/hetzner-k3s/issues/379

❗Do NOT add the ssh key of bastion into hetzner's ssh keys. If the fingerprint is present, then it will not be created by the script. Then the autocaled nodes won't have an ssh key on them, making them to ask you for root password change. Causing tons of trouble.

### Install cluster

`hetzner-k3s create --config config.yaml`

#### In case of failure

Exec Sum: Meanwhile there shouldn't be any.

##### On STDIN failure

See [here](https://github.com/vitobotta/hetzner-k3s/issues/379) for more about that

Update: Should be fixed now with the accepted PR.

Run this: 

```bash
export ver='v1.29.6+k3s2' master="10.0.0.3" # set to first master
echo 'curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$ver" sh - && systemctl stop k3s && rm -f /etc/initialized' | ssh root@$master bash
```



##### Fix If system-upgrade-controller is not running:

```bash
kubectl apply -f https://github.com/rancher/system-upgrade-controller/releases/latest/download/system-upgrade-controller.yaml
```

(fixing [this rancher problem](https://github.com/rancher/system-upgrade-controller/issues/302))

Update: Should be fixed meanwhile by rancher

### ssh config

With this in bastion's .ssh/config you can easily ssh into the masters:

```bash
admin@bastion:~/axc3$ cat $HOME/.ssh/config
Host m1
  HostName 10.0.0.5
  User root
Host m2
  HostName 10.0.0.3
  User root
Host m3
  HostName 10.0.0.4
  User root
```

IPs from the hetzner cloud UI.


### Celebrate

```
admin@bastion:~/axc3$ k get pods -A
NAMESPACE        NAME                                               READY   STATUS    RESTARTS   AGE
kube-system      cluster-autoscaler-84fd54d697-jqrsm                1/1     Running   0          16m
kube-system      coredns-576bfc4dc7-hd928                           1/1     Running   0          16m
kube-system      hcloud-cloud-controller-manager-7c697b4d54-tzt87   1/1     Running   0          16m
kube-system      hcloud-csi-controller-d97f9f5cd-swh2c              5/5     Running   0          16m
kube-system      hcloud-csi-node-2mphv                              3/3     Running   0          16m
kube-system      hcloud-csi-node-2p66j                              3/3     Running   0          15m
kube-system      hcloud-csi-node-wb6ql                              3/3     Running   0          16m
system-upgrade   system-upgrade-controller-7894d5bb99-p5czj         1/1     Running   0          6m22s
```

## Delete Kubectl API Loadbalancer

hetnzer-k3s does create an API Loadbalancer. Costs 8 Euros/month. Delete it, via the cloud console.
The cluster does not require that.

## Continue On Laptop

We did add our ssh key to all nodes, so we can jump on them via bastion.

### Tools

Install [binenv](https://github.com/devops-works/binenv). Then:

```bash
for t in kubectl kubens kubectx k9s helm; do binenv install $t; done
```


### ssh config

#### On Laptop

These are my (veery short) hostnames for the masters, via bastion ("b"). Adapt to your likings but you might see them in screenshots later.

```bash
Host b
  Hostname 37.27.42.244
  User admin
  LocalForward 6443 10.0.0.3:6443 # for kubectl

Host m1
  HostName 10.0.0.5
  User root
  ProxyCommand ssh -W %h:%p b

Host m2
  HostName 10.0.0.3
  User root
  ProxyCommand ssh -W %h:%p b

Host m3
  HostName 10.0.0.4
  User root
  ProxyCommand ssh -W %h:%p b
```

💡Yes, harcoded 10.0.0.3 - We could also tcp round robin balance from bastion to the 3 masters but its not worth the effort - when a master fails, go to another one via this .ssh/config. And hey, you do want to know when it fails, no?
Plus, you save 8 Euro/month, thanks to this.

```bash
export KUBECONFIG=~/.kubeconfig # I symlink any current one to this here.
```

Now copy kubeconfig and replace the LB IP (which you deleted) in kubeconfig with 127.0.0.1 via the portforward configured in your ssh config.

```bash
scp b:kubeconfig .
sed -i 's|https://[^:]*:|https://127.0.0.1:|' ./kubeconfig
```

Try k9s now - you have your cluster accessible on your laptop.



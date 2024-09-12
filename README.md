# Hetzner K3s Functions
> A collection of functions to setup K3s clusters on [Hetzner Cloud][hcloud], based on vitobotta's [hetzner-k3s][hk3s]


[![Tests](https://github.com/axgkl/hk3sf/actions/workflows/tests.yml/badge.svg)](https://github.com/axgkl/hk3sf/actions/workflows/tests.yml)

<img src="https://github.com/axgkl/hk3sf/actions/workflows/tests.yml/badge.svg"/> 

## About

[Hetzner-k3s][hk3s] is nicely engineered general k3s installation tool on Hetzner, with a large degree of declarative possibilities for customization. As terraform, it is a single static binary and idempotent, with a single source of truth. In contrast to terraform it is straightforward to use, with far less abstractions but a lot of built in best practices, incl CNI and autoscaling, plus faster.

This repo here provides a set of **bash functions**, incl. possibly useful support tools to organize them, in order to further automate _around_ the pure k3s installation, which hetzner-k3s provides.

## Not a Wrapper

❗ This repo is **not** meant to be a convenience wrapper, to get you to **your** k3s setup. Unmodified it works for me - but it won't for you. It is _neither_ meant to relief you off the effort to learn the underlying machinery, nor from adding/adjusting code, to customize!

> As nearly always, [Prime nails it](https://youtu.be/EvzB_Q1gSds?t=54).

So: **Only** if you _anyway_ would automate your cluster setup using bash scripts, you might find this useful, as a starting point.

*You **will** have to modify the functions to your needs, e.g. provide dns provisioning for **your** provider, since you won't use the [built in one](../pkg/dns.sh) (DO) and/or supply [ingress setup](../pkg/ingress.sh) functions, when **not** using nginx and so on.*  
What I _did_ aim for, is to make the places _where_ to customize as canonical as possible, plus provide blueprints, for _how_ to do it.

## Features

### Pre K3s Installation

Focus is on creating the cluster with private IPs only, and a _proxy_ server in front of them:

```mermaid
flowchart LR
    A[World] --> B[Bastion Proxy\nIP pub\nOpt.LoadBalancer]
    B --priv net--> M1[Master 1\n...\nMaster 3]
    B --priv net--> w1[Worker 1\n...\nWorker n]
    B --priv net--> a1[Autoscaled 1\n...\nAutoscaled n]
```

That bastion server is the only one with a public IP, and [can be equipped with a l4 loadbalancer](./docs/l4lb.md), forwarding the traffic into the cluster, like a hetzner loadbalancer would do.

💡 Using the bastion node as loadbalancer is optional. [hetzner-k3s][hk3s] does by default create hetzner loadbalancers for you, using the hetzner cloud controller manager (ccm).

[Here](./docs/l4lb.md) is a detailed description of the loadbalancer setup, incl. some reasons for it.

___

We provide the functions necessary to 

- create the private network
- bastion node itself, with ssh key
- tools (hetzner-k3s, kubectl, helm) and [optional load balancer service](./docs/l4lb.md) on it
- cloud init config for hetzner-k3s, so that the priv ip nodes can reach the internet

Then hetzner-k3s can be run from there, to create the cluster.

### K3s Installation

From the proxy server, we then kick off hetzner-k3s, using a config we synthesized from the environ.

[Here](./docs/privip.md) are the details regarding a private IP only cluster setup.

### Post K3s Installation

We provide functions to
- transfer kubeconfig from the bastion to the local machine
- configure local ssh
- install cert-manager into the cluster
- install ingress-nginx into the cluster
- install services using that ingress into the cluster, in a way so that https traffic from the world can reach the application pods with
  - working certificates
  - optional pod affinity via cookie ("sticky sessions")
  - source ip preservation (using [proxy protocol](https://www.haproxy.org/download/1.8/doc/proxy-protocol.txt))
  - autoscaling support 




## Usage

In general the script provides its functions after being sourced from a bash script _you_ provide and make executable.

See the ci [../tests/setup.sh](../tests/setup.sh) script for an example, which installs the full cluster from scratch.

💡 When you pass _arguments_ to that script, this results in an execution of the given function and exit of the script, w/o running the subsequent functions after sourcing. 

General layout of your script is therefore:

```bash
CONFIGVAR1=CONFIGVAL1
...
source <dir>/main.sh "$@" # causes exit when an arg is passed, i.e. a function name

setup_function1 
setup_function2 
...
```

`yourscript -h` lists all available functions.


## Customization

See [here](./docs/customization.md)


## Details

 [here](./docs/customization.md)
```
tests/test_setup.sh log 'cert' -f
1 sync.go:290] "failed to create Order resource due to bad request, marking Order as failed" err="429 urn:ietf:params:acme:error:rateLimited: Error creating new order :: too many certificates (5) already issued for this exact set of domains in the last 168 hours: hello-world.citest.mydomain.net, retry after 2024-08-14T01:31:39Z: see https://letsencrypt.org/docs/duplicate-certificate-limit/" logger="cert-manager.controller" resource_name="hello-world.citest.mydomain.net-tls-1-3489545008" resource_namespace="default" resource_kind="Order" resource_version="v1"
```

## K3s with: HA + AutoScaling + GitOps. 
> For < 20€/month. From Scratch.


## Refs

- [knowledge](./docs/knowledge.md)

- https://community.hetzner.com/tutorials/how-to-set-up-nat-for-cloud-networks
- https://github.com/vitobotta/hetzner-k3s
- https://github.com/vitobotta/hetzner-k3s/issues/379
- https://www.youtube.com/watch?v=u5l-F8nPumE&t=466s
- https://gimlet.io











### Topo: 3 Masters for k8s HA. No API LBs

Why: 

1. don't want to ever have to recover a broken k8s. So: 3.
2. => Workloads on (cheap) masters - but with **autoscaled** add/delete workers if required.

IPs: Priv IPs are for free -> Only 1 pub IP (on a bastion outside the k8s cluster, which runs trivially restorable services w/o k8s). Also more secure, only this to shield.

[Lets build the k3s cluster](./k3s.md)

## Play Time

If new to this world, check these:

- [ingress](./k8s_ingress.md)
- [autoscaling](./k8s_autoscaler.md)
- [csi](./k8s_csi.md)


Now check [here](./metal.md) regarding some pretty heavy metal stuff.  It's about how we wiped the need for a hetzner loadbalancer for services...

Edit: And it was in vain, see first paragraph there.

Now of the real solution regarding networking:

[Setting up networking](./netw.md)


https://www.haproxy.org/download/1.8/doc/proxy-protocol.txt

PROXY TCP4 192.168.0.1 192.168.0.11 56324 443
GET / HTTP/1.1
Host: 192.168.0.11
\r\n

SO_REUSEPORT in strace nc -l -p 80

[hk3s]: https://github.com/vitobotta/hetzner-k3s
[hcloud]: https://docs.hetzner.cloud/

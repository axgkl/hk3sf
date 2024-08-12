# Hetzner K3s Functions
> A collection of functions to setup K3s clusters on Hetzner Cloud, based on vitobotta's [hetzner-k3s](https://github.com/vitobotta/hetzner-k3s).

[![Tests](https://github.com/axgkl/hk3sf/actions/workflows/tests.yml/badge.svg)](https://github.com/axgkl/hk3sf/actions/workflows/tests.yml)

## About

https://youtu.be/EvzB_Q1gSds?t=54




## K3s with: HA + AutoScaling + GitOps. 
> For < 20€/month. From Scratch.


## Refs

- https://community.hetzner.com/tutorials/how-to-set-up-nat-for-cloud-networks
- https://github.com/vitobotta/hetzner-k3s
- https://github.com/vitobotta/hetzner-k3s/issues/379
- https://www.youtube.com/watch?v=u5l-F8nPumE&t=466s
- https://gimlet.io

```mermaid
flowchart LR
    A[World] --> B[Bastion\nIP pub, DNS]
    B --> M1[M1\nk3s master1\nIP priv]
    B --> M2
    B --> M3
    B -.-> A1[Autoscaled 1]
```



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



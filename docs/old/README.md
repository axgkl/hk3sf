# Older Notes
made these while playing with v1 of hetzner-k3s, flannel, before I made these little collection of functions around it.


Might still contain some useful infos, so I'll keep it around for now.

Note: we did also drop caddy ingress for nginx since session stickyness could not be done with it.

---


### Topo: 3 Masters for k8s HA. No API LBs


- [ingress](./k8s_ingress.md)
- [autoscaling](./k8s_autoscaler.md)
- [csi](./k8s_csi.md)

Now check [here](./metal.md) regarding some pretty heavy metal stuff. It's about how we wiped the need for a hetzner loadbalancer for services...

Edit: And it was in vain, see first paragraph there.

Now of the real solution regarding networking:

[Setting up networking](./netw.md)

<https://www.haproxy.org/download/1.8/doc/proxy-protocol.txt>

PROXY TCP4 192.168.0.1 192.168.0.11 56324 443
GET / HTTP/1.1
Host: 192.168.0.11
\r\n

SO_REUSEPORT in strace nc -l -p 80



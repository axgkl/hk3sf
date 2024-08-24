# Layer 4 Load Balancer

You don't necessarily need to use hetzner's layer 4 load balancer. 

Below we describe the mechanics of 'rolling your own', on the proxy server in front of your cluster. We use [mholt/caddy-l4][cl4] here, but nginx or traefik would work as well.


The function `ensure_proxy_is_loadbalancer` in [setup.sh](../setup.sh) installs caddy with the l4 extension and configures it to forward traffic to the cluster nodes, adding the [proxy protocol](https://www.haproxy.com/blog/use-the-proxy-protocol-to-preserve-a-clients-ip-address) header.

Below is a sample caddy config:


```json
root@citest-proxy:~# cat /opt/caddy/config.json
{
  "logging": {
    "sink": {
      "writer": {
        "output": "stdout"
      }
    },
    "logs": {
      "default": {
        "level": "DEBUG"
      }
    }
  },
  "apps": {
    "layer4": {
      "servers": {
        "port80": {
          "listen": [
            ":80",
            "[::]:80"
          ],
          "routes": [
            {
              "handle": [
                {
                  "handler": "proxy",
                  "proxy_protocol": "v2",
                  "upstreams": [
                    {
                      "dial": [
                        "10.1.0.3:30080"
                        "10.1.0.4:30080"
                        "10.1.0.5:30080"
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        },
        "port443": {
          "listen": [
            ":443",
            "[::]:443"
          ],
          "routes": [
            {
              "handle": [
                {
                  "handler": "proxy",
                  "proxy_protocol": "v2",
                  "upstreams": [
                    {
                      "dial": [
                        "10.1.0.3:30443"
                        "10.1.0.4:30443"
                        "10.1.0.5:30443"
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      }
    }
  }
}

```

## 📝 Note

This is forwarding http and https traffic to static Node Ports within the cluster, acting solely on layer 4. We provide the IPs of our 3 master nodes. 

## 💡Node Port

> A NodePort is a feature in Kubernetes that exposes a service to external traffic. It's one of the ways you can access the service within the cluster from outside.
> When a service is created with NodePort type, Kubernetes allocates a port from a predefined range (default is 30000-32767), and each Node will proxy that port (the same port number on every Node) into your service.
> External traffic that comes to the Node on the allocated port is forwarded to the service. Even if a service is running on a specific node, using NodePort allows the service to be accessible from other nodes in the cluster.

So: This works, when we configure our ingress within the cluster, with Node Ports 30080 and 30443.

In turn we do _not_ need to provide annotations for the hetzner ccm, which would automatically update the hetzner loadbalancer, when a new ingress port comes up.

=> If you have rather dynamics requirements, regarding open ports on the Internet, then use use hetzner's lb - or add the new port to the proxy lb manually in such occasions.

I'm not aware of some ccm, which could e.g. run http config commands on new ingress ports, so that we could provide a reconfig handler for such requests, on the proxy lb. Let me know via an issue, if you are.

---

Further reading: 

- https://medium.com/@panda1100/how-to-setup-layer-4-reverse-proxy-to-multiplex-tls-traffic-with-sni-routing-a226c8168826

[cl4]: https://github.com/mholt/caddy-l4

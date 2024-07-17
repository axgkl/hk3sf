# Understanding the Cluster Autoscaler

hetzner-k3s installed the cluster autoscaler for you. 

```bash
 …/docs/deploys/hello_autoscaler❯ k get pods -o wide -A | grep auto
kube-system      cluster-autoscaler-767d8cfb74-mddnl              1/1     Running   0          12h     10.244.0.6    axc3-cx22-master1   <none>           <none>
```

Deploy ./deploys/hello_autoscaler/hello.yml: `k apply -f hello.yml`

Note the node antiaffinity rule, so that it **has** to deploy the replicas on different nodes:

```yaml
     affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: "app"
                operator: In
                values:
                - xhello-world
            topologyKey: "kubernetes.io/hostname"
```

Play with the replicas, see how it scales up and down, creating the new nodes from the big autoscaler pool of our hetzner-k3s config.


When you scale **down**, it might happen that the normal k8s controller keeps a big node alive, since affinity rules are fulfilled by this as well:

```bash
  …/docs/deploys/hello_autoscaler❯ k get pods -o wide
NAME                            READY   STATUS    RESTARTS   AGE     IP            NODE                              NOMINATED NODE   READINESS GATES
xhello-world-6bf6c965df-2ph4p   1/1     Running   0          7h46m   10.244.0.9    axc3-cx22-master1                 <none>           <none>
xhello-world-6bf6c965df-5t95d   1/1     Running   0          7h46m   10.244.5.4    big-autoscaled-4036470b7d0c598c   <none>           <none>
xhello-world-6bf6c965df-m6dhg   1/1     Running   0          7h46m   10.244.2.9    axc3-cx22-master2                 <none>           <none>
```

But after 10 minutes or so, the cluster autoscaler kicks in:

```
W0717 05:47:56.634094       1 hetzner_servers_cache.go:94] Fetching servers from Hetzner API                                                  │
│ I0717 05:47:56.894643     1 hetzner_node_group.go:559] Set node group big-autoscaled size from 1 to 0, expected delta -1                    │
│ I
```

And the costly big nodes are gone:

```bash
  …/docs/deploys/hello_autoscaler❯ k get pods -o wide 
NAME                            READY   STATUS    RESTARTS   AGE     IP            NODE                NOMINATED NODE   READINESS GATES
xhello-world-6bf6c965df-2ph4p   1/1     Running   0          7h51m   10.244.0.9    axc3-cx22-master1   <none>           <none>
xhello-world-6bf6c965df-8ts5n   1/1     Running   0          62s     10.244.1.13   axc3-cx22-master3   <none>           <none>
xhello-world-6bf6c965df-m6dhg   1/1     Running   0          7h51m   10.244.2.9    axc3-cx22-master2   <none>           <none>
```

💡This totally rocks ✨


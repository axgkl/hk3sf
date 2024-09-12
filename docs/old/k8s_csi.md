# Understanding the Container Storage Interface (CSI) in Kubernetes

This is imho one of the killer feats of a k8s cluster:

```
Is there a way, that a node is processing, backed by data on a volume.
And when it crashes, k8s reallocates the pod to another healty node - AND REMOUNTS the data volume over to it?

  Copilot ───

Yes, Kubernetes supports this scenario through the use of Persistent Volumes (PV) and Persistent Volume Claims (PVC). 

A Persistent Volume (PV) is a piece of storage in the cluster that has been provisioned by an administrator or dynamically provisioned using Storage Classes. A Persistent Volume Claim (PVC) is a request for storage by a user.

When a pod is scheduled on a node, the PVC attached to the pod will be bound to a PV, and the storage resource will be mounted to the node and thus accessible to the pod. 

If the pod crashes or is rescheduled to another node, the PVC will be unbound from the PV and the storage resource will be unmounted from the original node. When the pod starts up on the new node, the PVC will be bound to the PV again, and the storage resource will be mounted to the new node. 

This ensures that the pod has access to the same data regardless of the node it is running on. 

Here is an example of how you can define a PVC in your pod configuration:

``yaml
apiVersion: v1
kind: Pod
metadata:
  name: mypod
spec:
  containers:
  - name: myfrontend
    image: nginx
    volumeMounts:
    - mountPath: "/var/www/html"
      name: mypd
  volumes:
  - name: mypd
    persistentVolumeClaim:
      claimName: myclaim
``

```

Let's try.


hetzner-k3s installed the hetzner-csi, which creates (ceph backed, i.e. HA) volumes.

We test it using the multipurpose weapon onechart: https://gimlet.io/docs/onechart-reference

## Config

```yaml
# values.yaml
image:
  repository: nginx
  tag: 1.19.3
vars:
  VAR_1: "value 1"
  VAR_2: "value 2"
ingress:
  host: hey.65.109.42.118.nip.io
  port: 82
  ingressClassName: nginx
volumes:
  - name: data
    path: /data
    size: 10Gi
    storageClass: hcloud-volumes
```

```bash
helm repo add onechart https://chart.onechart.dev
helm template my-release onechart/onechart -f values.yaml > manifest.yaml
k apply -f manifest.yaml
```

Test (assuming you ran the ingress tutorial and have the lb set up):

```bash
wget -q 'http://hey.65.109.42.118.nip.io/'  -O - | grep succ
<p>If you see this page, the nginx web server is successfully installed and

k get pvc
NAME              STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS     VOLUMEATTRIBUTESCLASS   AGE
my-release-data   Bound    pvc-5a747d7f-e187-4a48-90fb-096714be0e92   10Gi       RWO            hcloud-volumes   <unset>                 47m

```

fine (10Gig is the minimum)



Now e.g. via k9s, the s (shell) key, enter the pod and do this:

```bash
root@my-release-df876b76-vlkvj:/# date > /data/testfile
```

Now, via the hetzner UI, we shutdown(!) the node, where the service is running, in my case it was master2.

After 2,3 minutes:

```
  …/docs/deploys/hello_csi❯ k get pods -o wide|grep release                                                                               ?
my-release-df876b76-chw4f       0/1     ContainerCreating   0          40s    <none>        axc3-cx22-master3   <none>           <none>
my-release-df876b76-vlkvj       1/1     Terminating         0          30m    10.244.2.11   axc3-cx22-master2   <none>           <none>
```

...and it stays like that for 20 minutes. 😐  
Plus one big node came up- but as worker, not as master.

Last patience and booted up master2 again.

TODO: Investigate further why the volume was not detached and attached to a new pod. I mean, I understand that the waiting time must be long - imagine you = an admin who wants to install a new kernel, whatever. You want some long backoff time.

So now lets do it more friendly:

```bash
k scale deploy/my-release --replicas 0
deployment.apps/my-release scaled
```

```bash
❯ k get pods
NAME                            READY   STATUS    RESTARTS   AGE
my-release-df876b76-rktz9       1/1     Running   0          22s
 (...)

❯ k exec -ti my-release-df876b76-rktz9 bash
kubectl exec [POD] [COMMAND] is DEPRECATED and will be removed in a future version. Use kubectl exec [POD] -- [COMMAND] instead.
root@my-release-df876b76-rktz9:/# cat /data/testfile
Wed Jul 17 07:16:14 UTC 2024
```

💡Volumes are automatically reallocated when you ask k8s to e.g. drain a node.


Note: The big node automatically disappeared after booting up master 2 again.






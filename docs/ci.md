# CI Automation

We provide the possibility to run the cluster setup and various use cases and
tests, using a [CI pipeline](../.github/workflows/ci.yml). What _exactly_
[runs](https://github.com/axgkl/hk3sf/actions/runs/10841564368/job/30085787805)
at git pushes is parametrized by the commit messages.

See [here](../.github/workflows/ci.yml) which instructions are supported and also which github secrets are in use.

Notable parameters are:

- `:setup:` Creates the cluster, running [`tests/setup.sh`](../tests/setup.sh). When successful, you have a running k3s cluster, with ssl and ingress set up.
- `:keep:` Skips the teardown, the cluster will remain, until
- `:rm:` Removes the cluster, running [`tests/teardown.sh`](../tests/teardown.sh) script.

💡 Without `:keep:` the cluster will be destroyed it it was created by this run.

## Locally Running the CI Pipeline

- Export the [necessary](../.github/workflows/ci.yml) secrets to your environment
- Also export `$GITHUB_ACTIONS=true`, so that the test scripts do not try to source `tests/environ` (see below)
- Run any of the ci scripts, e.g. `test/setup.sh`

## Locally Accessing a Cluster Created by CI

If you provided `:keep:` in the commit message, when creating it, the cluster will remain and you can access it locally.

In order to access a cluster created by the CI pipeline, make sure you export the same private ssh key as `$SSH_KEY_PRIV`, which also the ci script had in _its_ environment, via a github secret, when the infrastructure was created by it.

💡 You do **not** have to provide a hetzner api token with _write_ access (`$HCLOUD_TOKEN_WRITE`), if you do not want to change the infrastructure but only access the cluster via kubectl. Same for the `$DNS_API_TOKEN` - not required locally, when no operation with it is planned.

- Source [`tests/environ`](../tests/environ), in bash or zsh.
- That set an alias `ci`, which provides access to all functions of this repo
- Fetch the kubeconfig with `ci enable_local_kubectl`, like the `setup.sh` script does as well:

```bash
  …/gitops❯ ci enable_local_kubectl                                          ✘!?
✔️ Loading module ./setup.sh
󰊕 get_kubeconfig
󰊕 link_kubeconfig
󰊕 set_localhost_to_kubeconfig
󰊕 set_ssh_config
󰊕 ssh_config_add_proxy_host
󰊕 ssh_config_add_master_host 1
󰊕 ssh_config_add_master_host 2
󰊕 ssh_config_add_master_host 3
✔️ Cluster hosts added
💡E.g. ssh citest-proxy or ssh citest-m1
󰊕 /home/gk/repos/ax/devapps/gitops/tests/ci-cluster.sh k get nodes
NAME             STATUS   ROLES                       AGE   VERSION
citest-master1   Ready    control-plane,etcd,master   8h    v1.30.2+k3s2
citest-master2   Ready    control-plane,etcd,master   8h    v1.30.2+k3s2
citest-master3   Ready    control-plane,etcd,master   8h    v1.30.2+k3s2

```

hf:

```bash
  …/gitops❯ ci servers .name                                                  ?⇡
citest-proxy
citest-master3
citest-master2
citest-master1
```



#!/usr/bin/env bash
export GITHUB_TOKEN="$GITOPS_TOKEN"
here=$(dirname $0)
source "$here/environ"
source "$here/../main.sh" "$@"

function clear_cluster {
    shw flux uninstall --silent
    for ns in default cert-manager ingress-nginx flux-system; do
        shw clear_namespace "$ns"
    done
}

shw ensure_local_kubectl force
shw flux ensure_tools
shw clear_cluster
# templ1="https://github.com/fluxcd/flux2-kustomize-helm-example"
shw flux_start_from_template_1 clean push
shw flux_bootstrap

false && . ../pkg/flux.sh && . ../pkg/kubectl.sh && . ../main.sh && . ../tools.sh || true

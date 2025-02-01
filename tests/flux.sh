#!/usr/bin/env bash

# typically called from within a flux monorepo root, e.g. local clone of git@github.com:axgkl/hk3sf-fluxtest.git!!

# templ1="https://github.com/fluxcd/flux2-kustomize-helm-example"
ALIASES='
f0:clear_cluster
f1:flux_init_repo_from_template_1
f2:flux_bootstrap
'
here=$(dirname $0)
source "$here/environ"
export GITHUB_TOKEN="$GITOPS_TOKEN"

function clear_cluster {
    shw flux uninstall --silent
    import clear_namespace
    for ns in default cert-manager ingress-nginx flux-system; do
        shw clear_namespace "$ns"
    done
}

source "$here/../main.sh"
shw report

false && . ../pkg/flux.sh && . ../pkg/kubectl.sh && . ../main.sh && . ../tools.sh || true

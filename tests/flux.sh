#!/usr/bin/env bash
export GITHUB_TOKEN="$GITOPS_TOKEN"

source "tests/environ"
source "./main.sh" "$@"
kubectl config current-context | grep -q "^$NAME-" || shw ensure_local_kubectl
shw flux ensure_tools

function clear_cluster {
    shw flux uninstall --silent
    for ns in default cert-manager ingress-nginx flux-system; do
        shw clear_namespace "$ns"
    done
}

function flux_test {
    shw cd ..

    shw git config user.name 'github-actions[bot]'
    shw git config user.email 'github-actions[bot]@users.noreply.github.com'

}
shw clear_cluster
(
    shw flux_test
)

false && . ../pkg/kubectl.sh && . ../main.sh && . ../tools.sh || true

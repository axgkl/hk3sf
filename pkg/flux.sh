doc='
currently we put the inital template into a subdir
so that docs and other stuff can reside outside of gitops checked repo

we derive this by from gitops path by the first dir in it.
'
BASEDIR='' # derived from GITOPS_PATH in vars function. sth like 'flux' or 'gitops', i.e. relative one level below the repo root.

# flux monorepo template as starting point
templ1="https://github.com/fluxcd/flux2-kustomize-helm-example"

#💡 Just alias support and ssh tunnel before any real flux cmd done by kube func
function flux {
    cmd="${1:-}"
    case "$cmd" in
    ct1) cmd=flux_clone_template_1 ;;
    s) cmd=flux_state ;;
    esac
    if [[ $cmd == flux_* || $cmd == ensure_* ]]; then
        shw "$cmd" "$@"
    else
        kube flux stream "$@" # ensures tunnel, continuous output
    fi
}
vars() {
    # e.g. axgkl from axgkl/hk3sf-fluxtest/staging
    BASEDIR="${GITOPS_PATH%%/*}"
    test -z "$BASEDIR" && die "GITOPS_PATH not set" "is: $GITOPS_PATH"
    GITOPS_BRANCH="${GITOPS_BRANCH:-main}"
    case "${GITOPS_HOST:-}" in
    gh | github) GITOPS_HOST=github.com ;;
    gl | gitlab) GITOPS_HOST=gitlab.com ;;
    *gitlab*) ;;
    *github*) ;;
    *) die "GITOPS_HOST not set/unknown" "is: $GITOPS_HOST" ;;
    esac
}

function flux_ensure_tools {
    for tool in yq flux age-keygen sops; do shw have "$tool" || shw binenv install "$tool"; done
}
shwgit() {
    shw "${1:-}"
    git add "$BASEDIR" && git commit -m "after $1" || true
}
clone_template() {
    test -e "$BASEDIR" && $clean && shw rm -rf "$BASEDIR"
    test -e "$BASEDIR" && die "Directory exists: $BASEDIR" "Remove or specify another directory for flux manifests"
    shw git clone "$templ1" "$BASEDIR"
    shw mv "$BASEDIR/.git" "$BASEDIR/.git.orig"
    touch .gitignore && git add .gitignore || true
    grep -q 'git.orig' .gitignore || echo "**/.git.orig/" >>.gitignore
    grep -q '/tmp' .gitignore || echo "/tmp.*" >>.gitignore
    git commit -m 'ignores' .gitignore || true
}

adapt_paths() {
    for d in apps clusters infrastructure; do repl_in_files "./$BASEDIR" "^  path: ./$d/" "  path: ./$BASEDIR/$d/"; done
}
function flux_reconcile {
    shw flux reconcile source git flux-system    # fetch into the cluster
    shw flux reconcile kustomization flux-system # apply within the cluster
    shw flux_state
}
function flux_init_repo_from_template_1 {
    vars
    local clean=true push=true
    for arg in "$@"; do
        case "$arg" in
        --noclean) clean=false ;;
        --nopush) push=false ;;
        *) die "unknown arg: $arg" ;;
        esac
    done

    git fetch
    git checkout -b new-branch "origin/$GITOPS_BRANCH"
    shwgit clone_template
    shwgit kustomize_nginx
    shwgit adapt_paths
    $push || return
    git checkout "$GITOPS_BRANCH"
    git reset --hard new-branch
    git branch -D new-branch
    git push origin "$GITOPS_BRANCH"
}

function flux_bootstrap {
    vars
    shw flux check --pre || die "flux pre-check failed"
    local f
    local t="${GITOPS_TOKEN:?Require GITOPS_TOKEN}"
    case "${GITOPS_HOST:-}" in
    *gitlab*) f=gitlab && export GITLAB_TOKEN="$t" ;;
    *github*) f=github && export GITHUB_TOKEN="$t" ;;
    esac
    shwgit flux_add_sops_master_key
    shw flux bootstrap "${f:-}" \
        --owner="${GITOPS_OWNER:?require GITOPS_OWNER}" \
        --path="${GITOPS_PATH:?require GITOPS_PATH}" \
        --repository="${GITOPS_REPO:?require GITOPS_REPO}" \
        --hostname="${GITOPS_HOST:?require GITOPS_HOST}" \
        --branch="${GITOPS_BRANCH:?require branch}" \
        --token-auth
    shw git pull
    shw flux check || die "flux post-check failed"
    shw flux_state
    flux_set_helpfull
}
function flux_set_helpfull {
    shw helpfull 'klog kustomize-controller;flux_state;klog nginx;kubectl describe svc ingress-nginx -n ingress-nginx'
}

function flux_add_sops_master_key {
    local ns='--namespace=flux-system'
    import render_namespace
    shw render_namespace flux-system | kube kubectl apply -f -
    local k="${FLUX_DECRYPT_SECRET:-}"
    test -z "$k" && {
        out "No FLUX_DECRYPT_SECRET set, generating new key..."
        shw age-keygen -o .age.priv
        k="$(grep SECRET <.age.priv)"
        grep -qF '*.priv' .gitignore || echo '*.priv' >>.gitignore
    }
    kubectl get secrets $ns | grep -q sops.age &&
        shw kubectl delete secret sops-age $ns
    echo -e "${k:-}" | grep -v '^$' | shw kubectl create secret generic sops-age \
        $ns --from-file=age.agekey=/dev/stdin
    echo -e "${k:-}" | shw age-keygen -y >"${BASEDIR:-}/sops.age.pub"
}

function flux_state {
    shw kubectl -n flux-system get GitRepository
    shw kubectl -n flux-system get Kustomization
}

# function ensure_flux_helm {
#     shw flux create source helm starboard-operator --url https://aquasecurity.github.io/helm-charts --namespace starboard-system
# }

function kustomize_nginx {
    local fn="${GITOPS_PATH:-}/infrastructure.yaml"
    sel='(select(.metadata.name == "infra-controllers")'
    yq eval ''"$sel"' | .spec.patches) = "REPLME"' "$fn" | repl 'REPLME' "$TNG" >"$fn.s"
    mv "$fn.s" "$fn"
}

# json patch, works:
# TNGs='
#     - patch: |
#         - op: add
#           path: /spec/values/controller/service/nodePorts
#           value: {}
#         - op: add
#           path: /spec/values/controller/config
#           value: {}
#         - op: add
#           path: /spec/values/controller/kind
#           value: DaemonSet
#         - op: add
#           path: /spec/values/controller/service/externalIPs
#           value: []
#         - op: replace
#           path: /spec/values/controller/service/nodePorts/http
#           value: 30080
#         - op: replace
#           path: /spec/values/controller/service/nodePorts/https
#           value: 30443
#         - op: replace
#           path: /spec/values/controller/config/use-proxy-protocol
#           value: "true"
#         - op: replace
#           path: /spec/values/controller/config/use-forwarded-headers
#           value: "true"
#       target:
#         kind: HelmRelease
#         name: ingress-nginx
# '
#
# strategic merge patch, works also:
TNG='
    - patch: |
        spec:
          values:
            controller:
              service:
                nodePorts:
                  http: 30080
                  https: 30443
                externalIPs: []
              config:
                use-proxy-protocol: "true"
                use-forwarded-headers: "true"
              kind: DaemonSet
      target:
        kind: HelmRelease
        name: ingress-nginx
'
false && . ./tools.sh && . ./conf.sh || true

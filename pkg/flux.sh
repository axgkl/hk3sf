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

function flux_ensure_tools {
    for tool in flux age-keygen sops; do shw have "$tool" || shw binenv install "$tool"; done
}
function flux_start_from_template_1 {
    local dir="${1:-flux}"
    test -e "$dir" && test "${2:-}" = "clean" && shift && shw rm -rf "$dir.orig" && shw mv "$dir" "$dir.orig"
    test -e "$dir" && die "Directory exists: $dir" "Remove or specify another directory"
    shw git clone "$templ1" "$dir"
    shw mv "$dir/.git" "$dir/.git.orig"
    shw git add .
    shw git commit -m "Initial flux template"
    test "${3:-}" = "push" && shift && shw git push
}
function set_gitops_host {
    case "${GITOPS_HOST:-}" in
    gh | github) GITOPS_HOST=github.com ;;
    gl | gitlab) GITOPS_HOST=gitlab.com ;;
    *gitlab*) ;;
    *github*) ;;
    *) die "GITOPS_HOST not set/unknown" "is: $GITOPS_HOST" ;;
    esac
}

function flux_bootstrap {
    shw flux check --pre || die "flux pre-check failed"
    local f
    local t="${GITOPS_TOKEN:?Require GITOPS_TOKEN}"
    set_gitops_host
    case "${GITOPS_HOST:-}" in
    *gitlab*) f=gitlab && export GITLAB_TOKEN="$t" ;;
    *github*) f=github && export GITHUB_TOKEN="$t" ;;
    esac
    shw flux bootstrap "${f:-}" \
        --owner="${GITOPS_OWNER:?require GITOPS_OWNER}" \
        --path="${GITOPS_PATH:?require GITOPS_PATH}" \
        --repository="${GITOPS_REPO:?require GITOPS_REPO}" \
        --hostname="${GITOPS_HOST:?require GITOPS_HOST}" \
        --branch="${GITOPS_BRANCH:-main}" \
        --token-auth
    shw flux check || die "flux post-check failed"
    shw flux_state
}
function flux_state {
    shw kubectl -n flux-system get GitRepository
    shw kubectl -n flux-system get Kustomization
}

# function ensure_flux_helm {
#     shw flux create source helm starboard-operator --url https://aquasecurity.github.io/helm-charts --namespace starboard-system
# }
false && . ./tools.sh && . ./conf.sh || true

templ1="https://github.com/fluxcd/flux2-kustomize-helm-example"

function flux {
    cmd="${1:-}"
    case "$cmd" in
    ct1 | clone_template) shift && shw flux_clone_template_1 "$@" ;;
    ensure_tools) shift && flux_ensure_tools "$@" ;;
    *) kube flux "$@" ;;
    esac
}
function flux_ensure_tools {
    for tool in flux age-keygen sops; do shw have "$tool" || shw binenv install "$tool"; done
}
function flux_clone_template_1 {
    local dir="${1:-flux}"
    test -e "$dir" && $force && shw rm -rf "$dir.orig" && shw mv "$dir" "$dir.orig"
    test -e "$dir" && die "Directory exists: $dir" "Remove or specify another directory"
    shw git clone "$templ1" "$dir"
    shw mv "$dir/.git" "$dir/.gitorig"
}

function ensure_flux_gh {
    shw flux check --pre || die "Pre-check failed"
    export GITHUB_TOKEN="${GH_GITOPS_TOKEN:-}"
    shw flux bootstrap github --owner="$GH_GITOPS_USER" --repository="other$GH_GITOPS_REPO" --branch=main --path=./clusters/my-cluster --personal
    shw flux check || die "flux post-check failed"
}

function ensure_flux_gl {
    export GITLAB_TOKEN="${GITOPS_TOKEN:?Require GL_GITOPS_TOKEN}"
    shw flux check --pre || die "flux pre-check failed"
    shw flux bootstrap gitlab \
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

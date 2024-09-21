function ensure_flux_gh {
    shw flux check --pre || die "Pre-check failed"
    export GITHUB_TOKEN="${GH_GITOPS_TOKEN:-}"
    shw flux bootstrap github --owner="$GH_GITOPS_USER" --repository="other$GH_GITOPS_REPO" --branch=main --path=./clusters/my-cluster --personal
    shw flux check || die "flux post-check failed"
}

function ensure_flux_gl {
    have flux || die "flux not installed" "run e.g. binenv install flux"
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

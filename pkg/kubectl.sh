# kubectl based ops
function clear_namespace() {
    test -z "${1:-}" && die "Usage: clear_namespace <namespace>"
    shw kubectl delete all --all -n "${1:-}" --ignore-not-found
    shw kubectl delete configmap,secret,pvc --all -n "${1:-}" --ignore-not-found
}
false && . ./tools.sh && . ./conf.sh || true

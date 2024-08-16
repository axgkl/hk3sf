#💡 CertManager
function ensure_cert_manager {
    # supports dns01, i.e. manages your DNS as well
    # https://cert-manager.io/docs/installation/helm/
    local m l d="./deploys/certmanager" rm=false

    while [[ -n "${1:-}" ]]; do case "$1" in
        --rm | rm) rm=true ;; # Remove cert-manager
        *) die "Unsupported" "$1" ;;
        esac && shift; done

    if $rm; then
        l="$(shw helm list -A)"
        grep -q cert-manager <<<"$l" && {
            shw helm delete cert-manager -n cert-manager
            shw kubectl delete crd \
                issuers.cert-manager.io \
                clusterissuers.cert-manager.io \
                certificates.cert-manager.io \
                certificaterequests.cert-manager.io \
                orders.acme.cert-manager.io \
                challenges.acme.cert-manager.io
        }
        ok "No more cert manager in your cluster"
        return
    fi
    test -z "$EMAIL" && die "EMAIL not set" "Set \$EMAIL, required for SSL"

    mkdir -p "$d"
    ok "Adding cert manager"
    shw helm repo add jetstack https://charts.jetstack.io --force-update
    shw helm upgrade --install \
        cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.15.2 \
        --set crds.enabled=true
    local fn="$d/issuer.yaml"
    shw render_issuer >"$fn"
    shw kubectl apply -f "$fn"
    shw test_cert_manager
    shw kubectl describe clusterissuer letsencrypt-prod
    ok "Cert Mgr and letsencrypt ClusterIusser installed\n${L}Ensure also nginx and you can run 'test_http_svc_nginx'$O"
}

#💡 Adding an issuer
function render_issuer {
    # when you supply a namespace, we'll create an issuer. Else a cluster issuer.
    # When he have a DNS_PROVIDER and TOKEN,and solver is auto we use the dns01 challenge, else http01
    local spec nsspec="" ingress="nginx" kind=ClusterIssuer solver=auto email="$EMAIL" namespace="cert-manager" type="letsencrypt-prod"
    while [[ -n "${1:-}" ]]; do
        case "$1" in
        e=* | email=*) email="${1##*=}" ;;
        t=* | type=*) type="${1##*=}" ;;
        i=* | ingress=*) ingress="${1##*=}" ;;
        s=* | solver=*) solver="${1##*=}" ;;
        N=* | namespace=*) kind=Issuer && namespace="${1##*=}" ;;
        *) die "Unsupported" "$1" ;;
        esac
        shift
    done
    if [[ "$kind" == "ClusterIssuer" ]]; then test -z "$email" && die "Email is required for ClusterIssuer"; fi
    if [[ "$type" =~ letsencrypt ]]; then
        if [ "$solver" == "auto" ]; then
            if [ -n "$DNS_PROVIDER" ] && [ -n "$DNS_API_TOKEN" ]; then solver=dns01; else solver='http01'; fi
        fi
        if [ "$solver" == "http01" ]; then
            solver="$(shw http01_solver "$ingress")"
        else # dns01
            solver="$(shw dns01_solver "$DNS_PROVIDER")"
            import add_secret
            shw add_secret "$DNS_PROVIDER-dns" access-token="\$DNS_API_TOKEN" namespace="$namespace" 1>&2
        fi
        spec="$(render_letsencrypt_spec "$email" "$type")"
    elif [[ "$type" =~ selfsigned ]]; then
        spec='  selfSigned: {}'
    fi
    import render_namespace
    if [[ -n "$namespace" ]]; then nsspec="$(render_namespace "$namespace")"; fi

    retval_=$(
        cat <<EOF
$nsspec
---
apiVersion: cert-manager.io/v1
kind: $kind
metadata:
  name: $type
  namespace: $namespace
spec:
$spec
EOF
    )
    echo -e "$retval_"
}

dns01_solver() {
    echo -e "
    - dns01:
        ${1:?provider required}:
          tokenSecretRef:
            name: ${1:-}-dns
            key: access-token
            "
}
http01_solver() {
    echo -e "
    - http01:
        ingress:
          class: ${1:?ingress requred}
    "
}

function render_letsencrypt_spec {
    cat <<EOF
  acme:
    email: ${1:?email required}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: ${2:?type required}-account-key
    solvers: $solver

EOF
}

function test_cert_manager {
    local fn="$CACHE_DIR/test-cert-manager.yaml"
    shw render_issuer type=test-selfsigned namespace=cert-manager-test >"$fn"
    echo -e '
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: selfsigned-cert
  namespace: cert-manager-test
spec:
  dnsNames:
    - example.com
  secretName: selfsigned-cert-tls
  issuerRef:
    name: test-selfsigned
' >>"$fn"
    shw kubectl apply -f "$fn"
    local cmd="kubectl get certificate -n cert-manager-test | grep True | grep -q selfsigned-cert"
    for _ in $(seq 1 10); do eval "$cmd" && break || sleep 1; done
    eval "$cmd" || die "Cert manager test failed" "💡 Check logs"
    ok "cert test passed"
    shw kubectl delete -f "$fn"
}
false && . ./tools.sh && . ./svc.sh && . ./main.sh || true

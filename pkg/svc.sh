function render_svc {
    retval_=''
    local ingr name="" hostname="" namespace=default ingress=nginx image="rancher/hello-world"
    local replicas=1

    for arg in "$@"; do
        case "$arg" in
        N=* | namespace=*) namespace="${arg#*=}" ;;
        r=* | replicas=*) replicas="${arg#*=}" ;;
        I=* | ingress=*) ingress="${arg#*=}" ;;
        i=* | image=*) image="${arg#*=}" ;;
        n=* | name=*) name="${arg#*=}" ;;
        *) out "not processed: $arg" ;;
        esac
    done

    test -z "$name" && die "name not set" "💡 Use n <name>"
    test i="nginx" && ingr=render_ingress_nginx || ingr="render_ingress_$ingress"
    import "$ingr"
    shw "$ingr" "$@"
    ingress="$retval_"

    local a=''
    retval_=$(
        cat <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
  labels:
    app: $name
spec:
  replicas: $replicas
  selector:
    matchLabels:
      app: $name
  template:
    metadata:
      labels:
        app: $name
    spec:
      containers:
      - name: $name
        image: $image
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: $name
spec:
  selector:
    app: $name
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80

$ingress
EOF
    )
    echo -e "$retval_"
}

function render_namespace {
    local f="${2:-/dev/stdout}" h=""
    test "${2:-}" && h="$(cat "$2")"
    echo -e "---
apiVersion: v1
kind: Namespace
metadata:
  name: ${1:?namespace required}
$h
" >"$f"
}

#💡 render_secret myname key=value key2=value2
function add_secret {
    # value can be '$foo' - it will be evaluated (to not show up in call logs)
    # we write the yqml file but with redacted values
    #
    local fn data="" pdta="" name="${1:-require name}" && namespace=default && shift
    v() {
        local full="$1"
        if [[ "${2:0:1}" == '$' ]]; then
            local v="${2:1}"
            retval_="$2" && v="${!v}"
        else
            retval_="${2:0:4}..." && v="$2"
        fi
        $full && echo -n "$v" || echo -n "[redacted: $retval_]"
    }

    for arg in "$@"; do
        case "$arg" in
        namespace=*) namespace="${arg#*=}" ;;
        *=*)
            key="${arg%%=*}" && value="${arg#*=}"
            data="$data  $key: $(v true "$value" | base64 --wrap=0)\n"
            pdta="$pdta  $key: $(v false "$value")\n"
            ;;
        *) die "Unsupported" "$arg" ;;
        esac
    done
    fn="./deploys/secrets/$name.yaml"
    mkdir -p "$(dirname "$fn")"
    test -z "$data" && die "data not set" "add_secret name key1=v1 'key2=\$myenvvar'" || true
    rs() {
        echo -e "---
apiVersion: v1
kind: Secret
metadata:
  name: $name
  namespace: $namespace
data:
$1
"
    }
    #echo -e "$(r "$data")" | kubectl apply -f -
    rs "$pdta" >"$fn"
    rs "$data" | kubectl apply -f -
}

false && . ./tools.sh && . ./pkg/ingress.sh || true

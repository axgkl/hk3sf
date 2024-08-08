function render_svc {
    retval_=''
    local ingr name="" hostname="" ingress=nginx image="rancher/hello-world"
    local replicas=1

    for arg in "$@"; do
        case "$arg" in
        r=* | replicas=*) replicas="${arg##*=}" ;;
        I=* | ingress=*) ingress="${arg##*=}" ;;
        i=* | image=*) image="${arg##*=}" ;;
        n=* | name=*) name="${arg##*=}" ;;
        *) ;;
        esac
    done
    echo "$@"
    test -z "$name" && die "name not set" "💡 Use n <name>"
    test i="nginx" && ingr=render_ingress_nginx || ingr="render_ingress_$ingress"
    import "$ingr"
    "$ingr" "$@"
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

false && . ./tools.sh && . ./pkg/ingress.sh || true

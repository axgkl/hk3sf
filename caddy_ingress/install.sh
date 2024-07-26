#!/usr/bin/env bash

kubectl create namespace caddy-system || true
helm template \
	--namespace=caddy-system \
	--repo https://caddyserver.github.io/ingress/ \
	--atomic \
	axcaddy \
	caddy-ingress-controller -f values.yaml >manifest.yaml
echo 'Hardcoding nodePort for http and https services'
sed -i '/targetPort: http$/a \ \ \ \ \ \ nodePort: 30080' manifest.yaml
sed -i '/targetPort: https$/a \ \ \ \ \ \ nodePort: 30443' manifest.yaml
kubectl apply -f manifest.yaml

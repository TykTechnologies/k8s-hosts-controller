#!/usr/bin/env bash
# Test the documented installation method

docker run --rm alpine:latest sh -c "
    apk add --no-cache curl &&
    curl -fsSL https://raw.githubusercontent.com/TykTechnologies/k8s-hosts-controller/main/install.sh | bash &&
    which k8s-hosts-controller &&
    k8s-hosts-controller --version
"

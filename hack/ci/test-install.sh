#!/usr/bin/env bash
# Test the documented installation method

docker run --rm alpine:latest sh -c "
    apk add --no-cache curl bash &&
    curl -fsSL https://raw.githubusercontent.com/TykTechnologies/k8s-hosts-controller/main/install.sh | VERSION=v0.0.1-beta.4 bash &&
    which k8s-hosts-controller &&
    k8s-hosts-controller --version
"

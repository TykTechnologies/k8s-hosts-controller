#!/usr/bin/env bash
# Usage: curl -fsSL https://raw.githubusercontent.com/TykTechnologies/k8s-hosts-controller/main/install.sh | bash
#
# Or install specific version:
#   VERSION=v0.1.0 curl -fsSL https://raw.githubusercontent.com/TykTechnologies/k8s-hosts-controller/main/install.sh | bash

# Copyright The Tyk Authors.
# Licensed under Apache 2.0

# Configuration with environment variable overrides
: ${BINARY_NAME:="k8s-hosts-controller"}
: ${VERSION:="v0.2.0"}  # Auto-updated during release - DO NOT EDIT MANUALLY
: ${INSTALL_DIR:="/usr/local/bin"}
: ${USE_SUDO:="true"}
: ${TMP_DIR:="/tmp"}

# Script version and info
REPO="TykTechnologies/k8s-hosts-controller"

HAS_CURL=false
HAS_WGET=false
OS=""
ARCH=""

# log prints a message to stdout
log() {
  echo "$*"
}

# fatal prints an error message and exits
fatal() {
  echo "Error: $*" >&2
  exit 1
}

# detectTools checks which tools are available
detectTools() {
  HAS_CURL="$(type "curl" &> /dev/null && echo true || echo false)"
  HAS_WGET="$(type "wget" &> /dev/null && echo true || echo false)"
}

# initArch discovers the architecture for this system
initArch() {
  ARCH=$(uname -m)
  case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
      echo "Unsupported architecture: $ARCH"
      echo "Supported: amd64, arm64"
      exit 1
      ;;
  esac
}

# initOS discovers the operating system for this system
initOS() {
  OS=$(echo $(uname) | tr '[:upper:]' '[:lower:]')
  case "$OS" in
    linux|darwin) ;;
    *)
      echo "Unsupported OS: $OS"
      echo "Supported: linux, darwin"
      exit 1
      ;;
  esac
}

# verifySupported checks if platform is supported and required tools exist
verifySupported() {
  local supported="darwin-amd64\ndarwin-arm64\nlinux-amd64\nlinux-arm64"
  if ! echo "${supported}" | grep -q "${OS}-${ARCH}"; then
    echo "No prebuilt binary for ${OS}-${ARCH}"
    echo "To build from source, go to https://github.com/${REPO}"
    exit 1
  fi

  if [ "${HAS_CURL}" != "true" ] && [ "${HAS_WGET}" != "true" ]; then
    echo "Either curl or wget is required"
    exit 1
  fi
}

# runAsRoot runs command as root if needed
runAsRoot() {
  if [ $EUID -ne 0 -a "$USE_SUDO" = "true" ]; then
    sudo "${@}"
  else
    "${@}"
  fi
}

# checkHttpCode checks if URL returns 200 OK
checkHttpCode() {
  local url="$1"
  local http_code=""

  if [[ -n "${HAS_CURL:-}" ]]; then
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  elif [[ -n "${HAS_WGET:-}" ]]; then
    http_code=$(wget -spider -S "$url" 2>&1 | grep "HTTP/" | awk '{print $2}' | tail -1)
  else
    return 1
  fi

  [[ "$http_code" == "200" ]]
}

# verifyReleaseAsset checks if the release asset exists before attempting download
verifyReleaseAsset() {
  local version="$1"
  local filename="${BINARY_NAME}_${version}_${OS}_${ARCH}.tar.gz"
  local release_url="https://github.com/${REPO}/releases/download/${version}/${filename}"

  log "Verifying release asset exists: $filename"

  if ! checkHttpCode "$release_url"; then
    fatal "Release asset not found: $filename

Available versions: https://github.com/${REPO}/releases

You can specify a different version:
  VERSION=v0.1.0 ./install.sh
"
  fi
}

# detectInstallDir determines the best installation directory
detectInstallDir() {
  # Check if we can write to INSTALL_DIR
  if [ -w "$INSTALL_DIR" ] 2>/dev/null; then
    return 0
  fi

  # Try sudo
  if [ "$USE_SUDO" = "true" ]; then
    if sudo -n true 2>/dev/null; then
      return 0
    fi
  fi

  # Fall back to home directory
  echo "No write access to $INSTALL_DIR"
  INSTALL_DIR="$HOME/.local/bin"
  USE_SUDO="false"
  mkdir -p "$INSTALL_DIR" 2>/dev/null || {
    echo "Failed to create $INSTALL_DIR"
    exit 1
  }

  echo "Installing to $INSTALL_DIR"

  # Warn about PATH
  if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "WARNING: $INSTALL_DIR not in PATH"
    echo "Add to PATH: export PATH=\"\$PATH:$INSTALL_DIR\""
  fi
}

# downloadFile downloads the binary package
downloadFile() {
  local filename="${BINARY_NAME}_${VERSION}_${OS}_${ARCH}.tar.gz"
  DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${filename}"

  echo "Downloading $DOWNLOAD_URL"

  TMP_ROOT="$(mktemp -dt k8s-hosts-installer-XXXXXX)"
  TMP_FILE="$TMP_ROOT/$filename"

  if [ "${HAS_CURL}" == "true" ]; then
    curl -SsL "$DOWNLOAD_URL" -o "$TMP_FILE"
  elif [ "${HAS_WGET}" == "true" ]; then
    wget -q -O "$TMP_FILE" "$DOWNLOAD_URL"
  fi

  if [ ! -f "$TMP_FILE" ]; then
    echo "Download failed"
    exit 1
  fi
}

# installFile extracts and installs the binary
installFile() {
  local tmp_dir="$TMP_ROOT/extracted"
  mkdir -p "$tmp_dir"

  echo "Extracting..."
  tar xf "$TMP_FILE" -C "$tmp_dir"

  echo "Installing $BINARY_NAME to $INSTALL_DIR"
  runAsRoot cp "$tmp_dir/$BINARY_NAME" "$INSTALL_DIR/"
  runAsRoot chmod +x "$INSTALL_DIR/$BINARY_NAME"

  echo "Successfully installed $BINARY_NAME to $INSTALL_DIR"
}

# installManagerScript downloads and installs the manager script
installManagerScript() {
  local script_url="https://raw.githubusercontent.com/${REPO}/main/hosts-controller-manager.sh"
  local tmp_script="$TMP_ROOT/hosts-controller-manager.sh"

  echo "Downloading manager script..."

  if [ "${HAS_CURL}" == "true" ]; then
    curl -SsL "$script_url" -o "$tmp_script"
  elif [ "${HAS_WGET}" == "true" ]; then
    wget -q -O "$tmp_script" "$script_url"
  fi

  runAsRoot cp "$tmp_script" "$INSTALL_DIR/hosts-controller-manager.sh"
  runAsRoot chmod +x "$INSTALL_DIR/hosts-controller-manager.sh"

  echo "Manager script installed to $INSTALL_DIR"
}

# cleanup removes temporary files
cleanup() {
  if [[ -d "${TMP_ROOT:-}" ]]; then
    rm -rf "$TMP_ROOT"
  fi
}

# fail_trap is executed on error
fail_trap() {
  result=$?
  if [ "$result" != "0" ]; then
    echo "Failed to install $BINARY_NAME"
    echo "For support, go to https://github.com/${REPO}/issues"
  fi
  cleanup
  exit $result
}

# verifyInstalled tests the installed binary
verifyInstalled() {
  set +e
  if ! command -v "$BINARY_NAME" &> /dev/null; then
    echo "$BINARY_NAME not found in PATH"
    echo "Installation directory: $INSTALL_DIR"
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
      echo "Add $INSTALL_DIR to PATH"
    fi
    exit 1
  fi
  set -e

  local version=$("$INSTALL_DIR/$BINARY_NAME" --version 2>/dev/null || echo "unknown")
  echo "$BINARY_NAME $version installed successfully"
}

# checkInstalledVersion checks if already installed
checkInstalledVersion() {
  if [[ -f "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
    local version=$("${INSTALL_DIR}/${BINARY_NAME}" --version 2>/dev/null || echo "")
    if [[ -n "$version" ]]; then
      echo "$BINARY_NAME $version is already installed"
      echo "Reinstalling..."
      return 1
    fi
  fi
  return 0
}

main() {
  echo "Installing $BINARY_NAME..."

  set -e
  trap "fail_trap" EXIT

  detectTools
  initArch
  initOS
  verifySupported
  verifyReleaseAsset "$VERSION"
  detectInstallDir

  checkInstalledVersion || true

  downloadFile
  installFile
  installManagerScript

  verifyInstalled
  cleanup

  trap - EXIT

  echo "Installation complete!"
  echo "Run: $BINARY_NAME --help"
}

main

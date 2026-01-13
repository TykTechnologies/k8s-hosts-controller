#!/usr/bin/env bash
# Usage: curl -fsSL https://raw.githubusercontent.com/TykTechnologies/k8s-hosts-controller/main/install.sh | bash
#
# Or install specific version:
#   curl -fsSL https://raw.githubusercontent.com/TykTechnologies/k8s-hosts-controller/main/install.sh | VERSION=v0.1.0 bash
#
# Or export and then install:
#   export VERSION=v0.1.0
#   curl -fsSL https://raw.githubusercontent.com/TykTechnologies/k8s-hosts-controller/main/install.sh | bash

readonly _version_="v0.0.1-beta.7"

: ${BINARY_NAME:="k8s-hosts-controller"}
: ${VERSION:=$_version_}  # Auto-updated during release - DO NOT EDIT MANUALLY
: ${INSTALL_DIR:="/usr/local/bin"}
: ${USE_SUDO:="true"}

if [ -z "$VERSION" ]; then
  echo "Error: Could not find current version"
  exit 1
fi

REPO="TykTechnologies/k8s-hosts-controller"

HAS_CURL=false
HAS_WGET=false
OS=""
ARCH=""

log() {
    echo "$*"
}

warn() {
    echo "Warning: $*" >&2
}

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
      fatal "Unsupported architecture: $ARCH. Supported: amd64, arm64"
      ;;
  esac
}

# initOS discovers the operating system for this system
initOS() {
  OS=$(echo $(uname) | tr '[:upper:]' '[:lower:]')
  case "$OS" in
    linux|darwin) ;;
    *)
      fatal "Unsupported OS: $OS. Supported: linux, darwin"
      ;;
  esac
}

# verifySupported checks if platform is supported and required tools exist
verifySupported() {
  local supported="darwin-amd64\ndarwin-arm64\nlinux-amd64\nlinux-arm64"
  if ! echo "${supported}" | grep -q "${OS}-${ARCH}"; then
    fatal "No prebuilt binary for ${OS}-${ARCH}. Build from source: https://github.com/${REPO}"
  fi

  if [ "${HAS_CURL}" != "true" ] && [ "${HAS_WGET}" != "true" ]; then
    fatal "curl or wget required to download files"
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

# checkHttpCode checks if URL is accessible (200 OK or 302 Redirect)
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

  # Accept 200 (OK) and 302 (Redirect) - GitHub releases use 302
  [[ "$http_code" == "200" || "$http_code" == "302" ]]
}

# verifyReleaseAsset checks if the release asset exists before attempting download
verifyReleaseAsset() {
  local version="$1"
  local filename="${BINARY_NAME}_${version}_${OS}_${ARCH}.tar.gz"
  local release_url="https://github.com/${REPO}/releases/download/${version}/${filename}"

  if ! checkHttpCode "$release_url"; then
    fatal "Release ${version} not found for ${OS}-${ARCH}. Available versions: https://github.com/${REPO}/releases"
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
  local original_dir="$INSTALL_DIR"
  INSTALL_DIR="$HOME/.local/bin"
  USE_SUDO="false"
  mkdir -p "$INSTALL_DIR" 2>/dev/null || {
    fatal "Cannot create installation directory: $INSTALL_DIR"
  }

  echo "No write access to $original_dir, using $HOME/.local/bin instead"
  # Warn about PATH if needed (will be checked at the end)
}

# downloadFile downloads the binary package
downloadFile() {
  local filename="${BINARY_NAME}_${VERSION}_${OS}_${ARCH}.tar.gz"
  DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${filename}"

  echo "Downloading ${BINARY_NAME} ${VERSION}..."

  TMP_ROOT="$(mktemp -dt k8s-hosts-installer-XXXXXX)"
  TMP_FILE="$TMP_ROOT/$filename"

  if [ "${HAS_CURL}" == "true" ]; then
    curl -SsL "$DOWNLOAD_URL" -o "$TMP_FILE"
  elif [ "${HAS_WGET}" == "true" ]; then
    wget -q -O "$TMP_FILE" "$DOWNLOAD_URL"
  fi

  if [ ! -f "$TMP_FILE" ]; then
    fatal "Download failed. Check your internet connection and try again"
  fi
}

# installFile extracts and installs the binary
installFile() {
  local tmp_dir="$TMP_ROOT/extracted"
  mkdir -p "$tmp_dir"

  echo "Installing ${BINARY_NAME} to ${INSTALL_DIR}..."
  tar xf "$TMP_FILE" -C "$tmp_dir"

  runAsRoot cp "$tmp_dir/$BINARY_NAME" "$INSTALL_DIR/"
  runAsRoot chmod +x "$INSTALL_DIR/$BINARY_NAME"
}

# installManagerScript downloads and installs the manager script
installManagerScript() {
  local script_url="https://raw.githubusercontent.com/${REPO}/main/hosts-controller-manager.sh"
  local tmp_script="$TMP_ROOT/hosts-controller-manager.sh"

  echo "Installing manager script..."

  if [ "${HAS_CURL}" == "true" ]; then
    curl -SsL "$script_url" -o "$tmp_script"
  elif [ "${HAS_WGET}" == "true" ]; then
    wget -q -O "$tmp_script" "$script_url"
  fi

  runAsRoot cp "$tmp_script" "$INSTALL_DIR/hosts-controller-manager.sh"
  runAsRoot chmod +x "$INSTALL_DIR/hosts-controller-manager.sh"
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
    echo "Error: Installation failed. For help: https://github.com/${REPO}/issues" >&2
  fi
  cleanup
  exit $result
}

# verifyInstalled tests the installed binary
verifyInstalled() {
  set +e

  # First check if binary actually exists in INSTALL_DIR
  if [[ ! -f "$INSTALL_DIR/$BINARY_NAME" ]]; then
    fatal "$BINARY_NAME not found at $INSTALL_DIR/$BINARY_NAME. Installation may have failed"
  fi

  # Check if it's in PATH
  if ! command -v "$BINARY_NAME" &> /dev/null; then
    echo "Successfully installed ${BINARY_NAME} to ${INSTALL_DIR}"
    echo ""
    echo "Warning: $INSTALL_DIR not in PATH. Add it with:"
    echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
    echo ""
    # Don't exit with error - installation succeeded
    return 0
  fi

  set -e

  echo "Successfully installed ${BINARY_NAME}"
}

# checkInstalledVersion checks if already installed
checkInstalledVersion() {
  if [[ -f "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
    local version=$("${INSTALL_DIR}/${BINARY_NAME}" --version 2>/dev/null || echo "")
    if [[ -n "$version" ]]; then
      echo "Reinstalling ${BINARY_NAME} (found ${version} installed)"
    fi
  fi
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

  checkInstalledVersion

  downloadFile
  installFile
  installManagerScript

  verifyInstalled
  cleanup

  trap - EXIT
}

main

#!/bin/bash
# Release preparation script
# Usage: ./hack/ci/release.sh v0.1.0

set -e

REPO="TykTechnologies/k8s-hosts-controller"
INSTALL_SH="hack/install.sh"

VERSION="$1"

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 v0.1.0"
  exit 1
fi

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9\.]+)?$ ]]; then
  echo "Invalid version format: $VERSION"
  echo "Expected format: v1.2.3 or v1.2.3-beta.4"
  exit 1
fi

if ! command -v gh &> /dev/null; then
  echo "Error: gh CLI not found. Install from https://cli.github.com/"
  exit 1
fi

if ! gh auth status &> /dev/null; then
  echo "Error: gh CLI not authenticated. Run: gh auth login"
  exit 1
fi

if git rev-parse "$VERSION" &> /dev/null; then
  echo "Error: Tag $VERSION already exists locally."
  echo "Use 'git tag -d $VERSION' to delete it, or choose a different version."
  exit 1
fi

if gh release view "$VERSION" --repo "$REPO" &> /dev/null; then
  echo "Error: Release $VERSION already exists on GitHub."
  exit 1
fi

CURRENT_VERSION=$(grep 'readonly _version_=' "$INSTALL_SH" | sed -E 's/.*_version_="([^"]*)".*/\1/')
if [ -z "$CURRENT_VERSION" ]; then
  echo "Error: Could not find current version in $INSTALL_SH"
  exit 1
fi

echo $CURRENT_VERSION

if [ "$VERSION" = "$CURRENT_VERSION" ]; then
  echo "install.sh already at version $VERSION"
else
  echo "Updating install.sh from $CURRENT_VERSION to $VERSION"
  sed -i.bak "s/readonly _version_=\".*\"/readonly _version_=\"$NEW_VERSION\"/" "$INSTALL_SH"
  rm "$INSTALL_SH".bak
fi

git add "$INSTALL_SH"
git commit -m "release: update install.sh to $VERSION"
echo "Created commit: $(git rev-parse --short HEAD)"

git tag -a "$VERSION" -m "Release $VERSION"
echo "Created tag: $VERSION"

echo "Pushing commit and tag..."
git push origin HEAD
git push origin "$VERSION"

echo ""
echo "Release preparation complete!"
echo "Monitor: https://github.com/$REPO/actions"

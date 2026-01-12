# Creating Releases with GoReleaser

## Prerequisites

1. Install GoReleaser:
```bash
go install github.com/goreleaser/goreleaser/v2@latest
```

2. Create a GitHub tag:
```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

3. Ensure GitHub token is set:
```bash
export GITHUB_TOKEN=$(gh auth token)
```

## Creating a Release

To create a full release:

```bash
goreleaser release --clean
```

This will:
- Run `go mod tidy` before building
- Build binaries for linux/amd64, linux/arm64, darwin/amd64, darwin/arm64
- Create tar.gz archives with README
- Generate SHA256 checksums
- Create a GitHub release with auto-generated changelog
- Inject version information via ldflags

## Testing Locally (Snapshot)

To test the build without creating a release:

```bash
goreleaser release --snapshot --clean --skip=publish
```

## Build Single Target

For faster iteration during development:

```bash
goreleaser build --snapshot --clean --single-target
```

## Verify Release

After release, users can install via:

1. **Download binary**: From GitHub Releases page
2. **Build from source**: `go build -o k8s-hosts-controller .`

## Version Information

Binaries built with goreleaser include embedded version information:
- `version`: Git tag (e.g., "v1.0.0")
- `commit`: Git commit SHA
- `date`: Build date
- `builtBy`: Build tool (e.g., "goreleaser")

Local builds have default values (version="dev", commit="none", etc.).


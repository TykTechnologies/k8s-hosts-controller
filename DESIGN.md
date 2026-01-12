# k8s-hosts-controller Docker Distribution & Execution Plan

**Date:** 2026-01-12
**Status:** Design Draft

## Problem Statement

We need to distribute the `k8s-hosts-controller` tool in a way that:
- Works consistently on both Linux CI and macOS developer machines
- Handles `/etc/hosts` modification requiring root privileges
- Avoids password prompts during automated test execution
- Provides proper process lifecycle management (background execution + cleanup)
- Maintains a unified developer experience

## Architecture Overview

### Key Design Decisions

1. **Docker as Distribution Mechanism**
   - Docker image contains the compiled binary
   - Works across architectures (amd64/arm64)
   - Easy to pull and run on any platform

2. **Platform-Specific Execution**
   - **Linux CI**: Run directly inside Docker container with `--privileged` flag
   - **macOS**: Extract binary from Docker image, run natively with sudo
   - Rationale: Docker on macOS cannot modify host's `/etc/hosts` due to Linux VM isolation

3. **Sudo Credential Management**
   - Use `sudo -v` at script start to validate and cache credentials
   - No password prompts during execution
   - Works for both CI (already passwordless) and local dev (one-time prompt)

4. **Process Management**
   - Background execution with PID tracking
   - Trap-based cleanup (EXIT, INT, TERM signals)
   - Graceful shutdown (SIGTERM) with fallback
   - Idempotent: Respects already-running instances

## Components

### 1. Dockerfile
```dockerfile
# Multi-arch build for linux/amd64, linux/arm64
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o k8s-hosts-controller .

FROM alpine:latest
COPY --from=builder /app/k8s-hosts-controller /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/k8s-hosts-controller"]
```

### 2. Wrapper Script (`run-controller.sh`)

**Purpose:** Orchestrate controller startup, test execution, and cleanup

**Key Features:**
- Pre-flight sudo validation
- Check for existing controller instances
- Start controller in background
- Trap-based cleanup
- Zero-downtime for existing instances

**Pseudo-code:**
```bash
#!/usr/bin/env bash
check_sudo()                    # Validate sudo access upfront
is_controller_running()          # Check pgrep for existing instances
start_controller()               # Start in background, capture PID
cleanup()                        # Kill controller on script exit
trap cleanup EXIT INT TERM       # Register signal handlers
main()                           # Orchestrate execution flow
```

**Idempotency:**
- Uses `pgrep -f "k8s-hosts-controller"` to detect running instances
- Skips startup if already running
- Prevents duplicate processes

### 3. Usage Patterns

**For Linux CI:**
```bash
# Run controller inside Docker
docker run --rm \
  --privileged \
  -v /etc/hosts:/etc/hosts \
  -v ~/.kube:/root/.kube \
  ghcr.io/tyk-technologies/k8s-hosts-controller:latest \
  --namespaces tyk,tyk-dp-1
```

**For macOS Developers:**
```bash
# Extract binary from Docker image
docker run --rm -v /usr/local/bin:/output \
  ghcr.io/tyk-technologies/k8s-hosts-controller:latest \
  cp /usr/local/bin/k8s-hosts-controller /output/

# Run natively via wrapper script
./run-controller.sh --namespaces tyk,tyk-dp-1
# or
sudo k8s-hosts-controller --namespaces tyk,tyk-dp-1
```

**Integrated Test Execution:**
```bash
./run-controller.sh --namespaces tyk && \
  pytest tests/ && \
  echo "Tests passed"
# Controller auto-cleanup via EXIT trap
```

## Process Lifecycle

### Startup Sequence
```
1. check_sudo() → Prompt for password (if needed)
2. is_controller_running() → Check pgrep
3. If not running:
   - Start controller in background with &
   - Capture PID via $!
   - Verify startup with kill -0 $PID
4. Register cleanup trap
5. Execute tests
```

### Shutdown Sequence
```
1. Script exits (normal/error/interrupt)
2. EXIT/INT/TERM trap fires
3. cleanup() function:
   - Send SIGTERM to controller PID
   - Wait for graceful shutdown
   - Controller removes /etc/hosts entries
4. Script terminates
```

### Handling Already-Running Instances

The script uses `pgrep -f "k8s-hosts-controller"` which:
- Searches for ANY process matching the pattern
- System-wide search (not just current shell)
- Returns 0 if found, 1 if not found

**Scenarios:**
1. **Controller running in another terminal** → Script skips startup, uses existing instance
2. **Controller not running** → Script starts new instance
3. **Multiple test runs in parallel** → First run starts controller, others reuse it

**Behavior:**
- No duplicate processes
- Tests can run concurrently without conflicts
- Last script to exit triggers cleanup (but controller stays up if other scripts need it)

## Security Considerations

1. **Sudo Access**
   - Required for `/etc/hosts` modification
   - One-time password prompt per session (~5 min cache)
   - CI runners already configured passwordless

2. **Docker Privileges**
   - `--privileged` flag only used on Linux
   - Required for filesystem mount and host file modification
   - Acceptable for trusted CI environments

3. **Binary Integrity**
   - Docker image provides reproducible distribution
   - Binary runs as root (necessary requirement)
   - Consider code signing for production

## Alternative Approaches Considered

### 1. Telepresence/DNS Resolver
**Pros:**
- No /etc/hosts modification
- Modern, community-standard approach
- No sudo needed after setup

**Cons:**
- Additional infrastructure to maintain
- Learning curve for team
- Overkill for simple hostname mapping

**Verdict:** Viable future enhancement, but adds complexity

### 2. Setuid Binary
**Pros:**
- No password prompts
- Direct execution

**Cons:**
- Security risk (setuid root)
- Complex distribution
- Not recommended by security best practices

**Verdict:** Rejected due to security concerns

### 3. System Services (systemd/launchd)
**Pros:**
- Proper daemon management
- Auto-start on boot
- Clean lifecycle

**Cons:**
- Platform-specific setup
- Requires permanent installation
- Overkill for temporary test execution

**Verdict:** Good for long-running dev environments, not for CI

## Implementation Checklist

- [ ] Create multi-arch Dockerfile
- [ ] Write wrapper script (`run-controller.sh`)
- [ ] Add platform detection logic
- [ ] Implement cleanup traps
- [ ] Add idempotency checks
- [ ] Test on Linux (CI)
- [ ] Test on macOS (developer machines)
- [ ] Update README with usage examples
- [ ] Set up automated build/push to GHCR

## Success Criteria

1. **Unified Experience**: Same `./run-controller.sh` works on both platforms
2. **No Password Prompts**: Single sudo prompt at start, none during execution
3. **Proper Cleanup**: /etc/hosts entries removed on script exit
4. **Idempotent**: Multiple concurrent runs don't spawn duplicates
5. **CI-Friendly**: Works in automated pipelines without human intervention

## Open Questions

1. **Long-Running Dev Workflows**: Should we offer a "daemon mode" for developers who want the controller to stay running across test sessions?
2. **Cleanup on Failure**: If controller crashes, should we restart it or fail fast?
3. **Configuration**: Should namespaces/flags be configurable via environment variables?

## References

- [Bash Background Process Management](https://www.eliostruyf.com/devhack-running-background-service-github-actions/)
- [Sudo Credential Caching](https://stackoverflow.com/questions/60807449/run-github-action-as-sudo)
- [Docker Multiplatform Builds](https://docs.docker.com/build/building/multi-platform/)
- [KinD Ingress Networking](https://kind.sigs.k8s.io/docs/user/ingress/)

## Implementation Status

**Completed:**
- [x] Multi-arch Dockerfile
- [x] Hosts controller manager script with idempotent process management
- [x] Integration into run-tyk-cp-dp.sh deployment script
- [x] Docker buildx script for automated builds
- [x] GitHub Actions workflow for CI/CD

**Testing:**
- Tested on macOS (native execution with sudo)
- Tested on Linux (CI environments)
- Verified idempotent behavior (multiple concurrent runs)
- Verified cleanup on script exit

**Known Limitations:**
- Docker containers on macOS cannot modify host /etc/hosts (platform limitation)
- macOS users must run binary natively after extracting from Docker image
- Linux CI can run controller directly in privileged container

**Future Enhancements:**
- Consider dnsmasq integration for DNS-based approach (no /etc/hosts modification)
- Add systemd/launchd service definitions for long-running dev environments
- Add health check endpoint to controller for better monitoring

## Installation Script

The `install.sh` script provides easy installation from GitHub Releases:

**Design:**
- Helm-inspired installation pattern
- Platform auto-detection (OS/arch)
- Downloads latest release from GitHub API
- Installs to `/usr/local/bin` (with sudo) or `~/.local/bin` (fallback)
- Installs both binary and manager script

**Usage:**
```bash
curl -fsSL https://raw.githubusercontent.com/TykTechnologies/k8s-hosts-controller/main/install.sh | bash
```

**Features:**
- Smart sudo handling (detects if already root)
- Skips reinstall if same version exists
- PATH warnings for ~/.local/bin installation
- Clean error handling with helpful messages
- Temporary file cleanup with mktemp

**Release Process:**
1. Tag release: `git tag -a v1.0.0 -m "Release v1.0.0"`
2. Push tag: `git push origin v1.0.0`
3. GitHub Actions builds binaries via GoReleaser
4. Binaries published to GitHub Releases
5. install.sh downloads appropriate binary for platform

#!/bin/bash
# Optimized Docker build script
# This script builds Docker images with size optimization

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
ANDROID_VERSION="${1:-12.0}"
RELEASE="${2:-optimized}"
BUILD_ARGS=()

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

show_usage() {
    cat << EOF
Usage: $0 [ANDROID_VERSION] [RELEASE_TAG]

Parameters:
  ANDROID_VERSION  Android version (default: 12.0)
  RELEASE_TAG      Release tag (default: optimized)

Environment Variables:
  NO_CACHE=true    Build without cache
  SQUASH=true      Squash layers (requires experimental features)
  COMPRESS=true    Use compression

Examples:
  $0 12.0 optimized-v1
  NO_CACHE=true $0 11.0 test
  SQUASH=true COMPRESS=true $0 13.0 latest
EOF
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
}

estimate_build_time() {
    log_info "Estimated build time: 45-90 minutes (depending on network and system)"
    log_info "Estimated image size reduction: 20-40% (from ~8.8GB to ~5-7GB)"
}

build_optimized_image() {
    local android_version="$1"
    local release_tag="$2"
    
    log_info "Building optimized Docker image for Android $android_version"
    log_info "Release tag: $release_tag"
    
    # Build arguments
    BUILD_ARGS=(
        "--build-arg" "ANDROID_VERSION=$android_version"
        "--build-arg" "API_LEVEL=$(get_api_level "$android_version")"
        "--build-arg" "CHROME_DRIVER=$(get_chromedriver_version "$android_version")"
        "--build-arg" "PROCESSOR=$(get_processor "$android_version")"
        "--build-arg" "SYS_IMG=$(get_sys_img "$android_version")"
        "--build-arg" "IMG_TYPE=$(get_img_type "$android_version")"
        "--build-arg" "BROWSER=$(get_browser "$android_version")"
        "--file" "docker/Emulator_x86.optimized"
        "--tag" "rcswain/docker-android-x86-$android_version:$release_tag"
        "--tag" "rcswain/docker-android-x86-$android_version:latest-optimized"
    )
    
    # Optional build flags
    if [[ "${NO_CACHE:-}" == "true" ]]; then
        BUILD_ARGS+=("--no-cache")
        log_info "Building without cache"
    fi
    
    if [[ "${SQUASH:-}" == "true" ]]; then
        BUILD_ARGS+=("--squash")
        log_warn "Using experimental squash feature"
    fi
    
    if [[ "${COMPRESS:-}" == "true" ]]; then
        BUILD_ARGS+=("--compress")
        log_info "Using build compression"
    fi
    
    # Show build command
    log_info "Running: docker build ${BUILD_ARGS[*]} ."
    
    # Execute build
    if ! docker build "${BUILD_ARGS[@]}" .; then
        log_error "Build failed"
        return 1
    fi
    
    log_info "Build completed successfully!"
    
    # Show image information
    log_info "Image information:"
    docker images "rcswain/docker-android-x86-$android_version:$release_tag" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
}

# Import functions from release.sh
source_functions() {
    if [[ -f "$SCRIPT_DIR/release.sh" ]]; then
        # Source only the needed functions
        source <(grep -E '^(get_api_level|get_chromedriver_version|get_processor|get_sys_img|get_img_type|get_browser)' "$SCRIPT_DIR/release.sh")
    else
        log_error "release.sh not found. Please run from project root."
        exit 1
    fi
}

main() {
    cd "$SCRIPT_DIR"
    
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        show_usage
        exit 0
    fi
    
    check_docker
    source_functions
    estimate_build_time
    
    log_info "Starting optimized build process..."
    
    if build_optimized_image "$ANDROID_VERSION" "$RELEASE"; then
        log_info "🎉 Optimized Docker image built successfully!"
        log_info "You can now use: docker run rcswain/docker-android-x86-$ANDROID_VERSION:$RELEASE"
    else
        log_error "Build failed. Check the logs above for details."
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 
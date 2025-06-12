#!/bin/bash
# Optimized Docker build script
# This script builds Docker images with size optimization

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values (don't override environment variables)
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
    
    # Determine Docker registry and image name
    local docker_registry="${DOCKER_USERNAME:-budtmo}"
    local image_name="$docker_registry/docker-android"
    local image_tag="emulator_$android_version"
    
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
        "--tag" "$image_name:$image_tag"
        "--tag" "$image_name:$image_tag-optimized"
    )
    
    # Add additional tags if release tag is provided
    if [[ "$release_tag" != "optimized" ]]; then
        BUILD_ARGS+=("--tag" "$image_name:$image_tag-$release_tag")
    fi
    
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
    docker images "$image_name:$image_tag" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    
    # Push to registry if credentials are available
    if [[ -n "${DOCKER_USERNAME:-}" ]] && [[ -n "${DOCKER_PASSWORD:-}" ]]; then
        log_info "Pushing images to Docker Hub..."
        
        # Push all tags
        docker push "$image_name:$image_tag"
        docker push "$image_name:$image_tag-optimized"
        
        if [[ "$release_tag" != "optimized" ]]; then
            docker push "$image_name:$image_tag-$release_tag"
        fi
        
        log_info "Images pushed successfully!"
    else
        log_warn "Docker credentials not found. Images built but not pushed."
        log_info "To push manually:"
        log_info "  docker push $image_name:$image_tag"
        log_info "  docker push $image_name:$image_tag-optimized"
    fi
}

# Android version helper functions (copied from release.sh to avoid conflicts)
get_api_level() {
    case "$1" in
        "5.0.1") echo "21" ;;
        "5.1.1") echo "22" ;;
        "6.0") echo "23" ;;
        "7.0") echo "24" ;;
        "7.1.1") echo "25" ;;
        "8.0") echo "26" ;;
        "8.1") echo "27" ;;
        "9.0") echo "28" ;;
        "10.0") echo "29" ;;
        "11.0") echo "30" ;;
        "12.0") echo "31" ;;
        "13.0") echo "33" ;;
        "14.0") echo "34" ;;
        "15.0") echo "35" ;;
        "16.0") echo "36" ;;
        *) echo "" ;;
    esac
}

get_chromedriver_version() {
    case "$1" in
        "5.0.1") echo "2.21" ;;
        "5.1.1") echo "2.13" ;;
        "6.0") echo "2.18" ;;
        "7.0") echo "2.23" ;;
        "7.1.1") echo "2.28" ;;
        "8.0") echo "2.31" ;;
        "8.1") echo "2.33" ;;
        "9.0") echo "2.40" ;;
        "10.0") echo "74.0.3729.6" ;;
        "11.0") echo "83.0.4103.39" ;;
        "12.0") echo "92.0.4515.107" ;;
        "13.0") echo "104.0.5112.29" ;;
        "14.0") echo "114.0.5735.90" ;;
        "15.0") echo "114.0.5735.90" ;;
        "16.0") echo "137.0.7151.70" ;;
        *) echo "" ;;
    esac
}

get_img_type() {
    case "$1" in
        5.0.1|5.1.1) echo "default" ;;
        *) echo "google_apis" ;;
    esac
}

get_browser() {
    case "$1" in
        5.0.1|5.1.1|6.0) echo "browser" ;;
        *) echo "chrome" ;;
    esac
}

get_processor() {
    case "$1" in
        9.0) echo "x86_64" ;;
        *) echo "x86_64" ;;
    esac
}

get_sys_img() {
    case "$1" in
        8.1) echo "x86" ;;
        9.0) echo "x86_64" ;;
        *) echo "x86_64" ;;
    esac
}

main() {
    cd "$SCRIPT_DIR"
    
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        show_usage
        exit 0
    fi
    
    # Use environment variables if available, otherwise use parameters or defaults
    local android_version="${ANDROID_VERSION:-${1:-12.0}}"
    local release_tag="${TRAVIS_TAG:-${2:-optimized}}"
    
    check_docker
    estimate_build_time
    
    log_info "Starting optimized build process..."
    log_info "Android Version: $android_version"
    log_info "Release Tag: $release_tag"
    
    if build_optimized_image "$android_version" "$release_tag"; then
        local docker_registry="${DOCKER_USERNAME:-budtmo}"
        local image_name="$docker_registry/docker-android"
        local image_tag="emulator_$android_version"
        
        log_info "🎉 Optimized Docker image built successfully!"
        log_info "You can now use: docker run $image_name:$image_tag"
    else
        log_error "Build failed. Check the logs above for details."
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 
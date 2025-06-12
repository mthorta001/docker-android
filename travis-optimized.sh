#!/bin/bash
# Optimized Travis build script for Docker Android images
# This script is specifically designed for building optimized Docker images
set -euo pipefail  # Strict mode: exit on error, exit on undefined variable, exit on pipe failure

# Android version mapping - short version to full version
get_android_version() {
    case "$1" in
        "5"|"5.0") echo "5.0.1" ;;
        "5.1") echo "5.1.1" ;;
        "6") echo "6.0" ;;
        "7") echo "7.0" ;;
        "7.1") echo "7.1.1" ;;
        "8") echo "8.0" ;;
        "8.1") echo "8.1" ;;
        "9") echo "9.0" ;;
        "10") echo "10.0" ;;
        "11") echo "11.0" ;;
        "12") echo "12.0" ;;
        "13") echo "13.0" ;;
        "14") echo "14.0" ;;
        "15") echo "15.0" ;;
        "16") echo "16.0" ;;
        *) echo "$1" ;;  # Return original if no mapping found
    esac
}

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_build() {
    echo -e "${BLUE}[BUILD]${NC} $*" >&2
}

# Show script usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

This script builds optimized Docker Android images using the optimized build process.

Environment Variables:
  ANDROID_VERSION    Android version to build (required for builds)
  TRAVIS_TAG         Release tag (required for builds)
  DOCKER_USERNAME    Docker Hub username (required for push)
  DOCKER_PASSWORD    Docker Hub password (required for push)
  
  BUILD_OPTIONS      Additional Docker build options (optional)
  NO_CACHE          Set to 'true' to build without cache
  SQUASH           Set to 'true' to squash image layers
  COMPRESS         Set to 'true' to enable compression

Examples:
  # Run tests only
  $0
  
  # Build with environment variables
  ANDROID_VERSION=12.0 TRAVIS_TAG=v1.21.0 $0
  
  # Build with optimization options
  NO_CACHE=true SQUASH=true ANDROID_VERSION=14.0 TRAVIS_TAG=latest $0

Options:
  -h, --help        Show this help message
  -v, --version     Show version information
  --test-only       Run tests only, skip build
  --no-push         Build but don't push to registry
EOF
}

# Validate environment
validate_environment() {
    local errors=0
    
    # Check for required build tools
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        ((errors++))
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed or not in PATH"
        ((errors++))
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        ((errors++))
    fi
    
    return $errors
}

# Secure Docker login
docker_login() {
    if [[ -z "${DOCKER_USERNAME:-}" ]] || [[ -z "${DOCKER_PASSWORD:-}" ]]; then
        log_error "Docker credentials not provided"
        log_error "Please set DOCKER_USERNAME and DOCKER_PASSWORD environment variables"
        return 1
    fi
    
    log_info "Logging in to Docker Hub as ${DOCKER_USERNAME}..."
    # Use stdin to avoid password in command line and process list
    if ! echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin; then
        log_error "Failed to login to Docker Hub"
        return 1
    fi
    
    log_info "Successfully logged in to Docker Hub"
}

# Docker logout
docker_logout() {
    log_info "Logging out of Docker Hub..."
    docker logout || log_warn "Failed to logout from Docker Hub"
}

# Run unit tests
run_tests() {
    log_info "Running unit tests..."
    log_info "Using pytest for testing"
    
    # Install test dependencies if needed
    if [[ -f "requirements.txt" ]]; then
        log_info "Installing Python dependencies..."
        python3 -m pip install --upgrade pip
        python3 -m pip install -r requirements.txt
    fi
    
    # Run tests
    if ! python3 -m pytest tests/ -v --tb=short; then
        log_error "Unit tests failed"
        return 1
    fi
    
    log_info "✅ All unit tests passed"
}

# Build optimized Docker image
build_optimized_image() {
    local android_version="$1"
    local release_tag="$2"
    
    # Map version if needed
    local mapped_version
    mapped_version=$(get_android_version "$android_version")
    
    log_build "Building optimized Docker image for Android $mapped_version"
    log_build "Release tag: $release_tag"
    
    # Set environment variables for build script
    export ANDROID_VERSION="$mapped_version"
    export TRAVIS_TAG="$release_tag"
    
    # Set build options from environment
    if [[ "${NO_CACHE:-}" == "true" ]]; then
        export BUILD_OPTIONS="${BUILD_OPTIONS:-} --no-cache"
        log_build "Building without cache"
    fi
    
    if [[ "${SQUASH:-}" == "true" ]]; then
        export BUILD_OPTIONS="${BUILD_OPTIONS:-} --squash"
        log_build "Using layer squashing"
    fi
    
    if [[ "${COMPRESS:-}" == "true" ]]; then
        export BUILD_OPTIONS="${BUILD_OPTIONS:-} --compress"
        log_build "Using build compression"
    fi
    
    # Make build script executable
    chmod +x build-optimized.sh
    
    # Execute optimized build
    log_build "Executing optimized build script..."
    if ! ./build-optimized.sh; then
        log_error "Optimized build failed for Android $mapped_version"
        return 1
    fi
    
    log_build "✅ Successfully built optimized image for Android $mapped_version"
}

# Execute build process for Android emulator
execute_optimized_build() {
    local android_version="$1"
    local release_tag="$2"
    local skip_push="${3:-false}"
    
    log_info "=== Starting Optimized Build Process ==="
    log_info "Android Version: $android_version"
    log_info "Release Tag: $release_tag"
    log_info "Skip Push: $skip_push"
    
    # Run tests first
    if ! run_tests; then
        log_error "Tests failed, aborting build"
        return 1
    fi
    
    # Build the optimized image
    if ! build_optimized_image "$android_version" "$release_tag"; then
        log_error "Image build failed"
        return 1
    fi
    
    # Push to registry unless skipped
    if [[ "$skip_push" != "true" ]]; then
        if ! docker_login; then
            log_error "Docker login failed, cannot push images"
            return 1
        fi
        
        log_build "Images will be pushed by build-optimized.sh"
        
        # Logout after build (build script handles push)
        docker_logout
    else
        log_info "Skipping push to registry as requested"
    fi
    
    log_info "🎉 Optimized build process completed successfully!"
}

# Main execution logic
main() {
    local test_only=false
    local no_push=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--version)
                echo "travis-optimized.sh v1.0.0 - Optimized Docker Android Builder"
                exit 0
                ;;
            --test-only)
                test_only=true
                shift
                ;;
            --no-push)
                no_push=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate environment
    if ! validate_environment; then
        log_error "Environment validation failed"
        exit 1
    fi
    
    # If only testing is requested
    if [[ "$test_only" == "true" ]]; then
        log_info "Running tests only (--test-only specified)"
        run_tests
        exit $?
    fi
    
    # Check if this is a tagged release or if we have required variables
    if [[ -z "${TRAVIS_TAG:-}" ]]; then
        log_info "No TRAVIS_TAG found - running tests only"
        run_tests
        exit $?
    fi
    
    if [[ -z "${ANDROID_VERSION:-}" ]]; then
        log_error "ANDROID_VERSION environment variable is required for builds"
        log_error "Supported versions: 12.0, 14.0, 15.0, 16.0"
        exit 1
    fi
    
    # Execute optimized build
    local success=true
    if ! execute_optimized_build "$ANDROID_VERSION" "$TRAVIS_TAG" "$no_push"; then
        success=false
    fi
    
    # Exit with appropriate code
    if [[ "$success" != "true" ]]; then
        log_error "Optimized build process failed"
        exit 1
    fi
    
    log_info "🚀 All operations completed successfully!"
}

# Cleanup function
cleanup() {
    local exit_code=$?
    log_info "Cleaning up..."
    
    # Ensure we logout from Docker Hub
    if docker info &> /dev/null; then
        docker_logout 2>/dev/null || true
    fi
    
    # Remove any temporary files if created
    # (Add cleanup logic here if needed)
    
    exit $exit_code
}

# Set up cleanup trap
trap cleanup EXIT INT TERM

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 
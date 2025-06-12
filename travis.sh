#!/bin/bash
# Bash version should >= 4 to be able to run this script.
set -euo pipefail  # Strict mode: exit on error, exit on undefined variable, exit on pipe failure

# Android version mapping - short version to full version
declare -A readonly ANDROID_VERSION_MAP=(
    [5]="5.0.1"
    [5.0]="5.0.1"
    [5.1]="5.1.1"
    [6]="6.0"
    [7]="7.0"
    [7.1]="7.1.1"
    [8]="8.0"
    [8.1]="8.1"
    [9]="9.0"
    [10]="10.0"
    [11]="11.0"
    [12]="12.0"
    [13]="13.0"
    [14]="14.0"
    [15]="15.0"
    [16]="16.0"
)

# Logging functions
log_info() {
    echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

# Map Android version from short to full format
map_android_version() {
    local input_version="$1"
    
    # If already a full version (contains dot), return as is
    if [[ "$input_version" == *.* ]]; then
        echo "$input_version"
        return 0
    fi
    
    # Try to map short version to full version
    if [[ -n "${ANDROID_VERSION_MAP[$input_version]:-}" ]]; then
        echo "${ANDROID_VERSION_MAP[$input_version]}"
        return 0
    fi
    
    # If no mapping found, return original version
    echo "$input_version"
}

# Secure Docker login
docker_login() {
    if [[ -z "${DOCKER_USERNAME:-}" ]] || [[ -z "${DOCKER_PASSWORD:-}" ]]; then
        log_error "Docker credentials not provided"
        exit 1
    fi
    
    log_info "Logging in to Docker Hub..."
    # Use stdin to avoid password in command line
    echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
}

# Docker logout
docker_logout() {
    log_info "Logging out of Docker Hub..."
    docker logout
}

# Execute build for Android emulator
execute_android_build() {
    local android_version="$1"
    local release_tag="$2"
    
    # Map version if needed
    local mapped_version
    mapped_version=$(map_android_version "$android_version")
    
    log_info "Original version: $android_version, Mapped version: $mapped_version"
    log_info "Running unit tests, building Docker images and pushing to Docker Hub"
    
    if ! bash release.sh all "$mapped_version" "$release_tag"; then
        log_error "Failed to build Android $mapped_version"
        return 1
    fi
}

# Execute build for real device
execute_real_device_build() {
    local release_tag="$1"
    
    log_info "Building Docker images for real device support and pushing to Docker Hub"
    
    if ! bash release_real.sh all "$release_tag"; then
        log_error "Failed to build real device images"
        return 1
    fi
}

# Execute build for Genymotion
execute_genymotion_build() {
    local release_tag="$1"
    
    log_info "Building Docker images for Genymotion support and pushing to Docker Hub"
    
    if ! bash release_genymotion.sh all "$release_tag"; then
        log_error "Failed to build Genymotion images"
        return 1
    fi
}

# Main execution logic
main() {
    # Check if this is a tagged release
    if [[ -z "${TRAVIS_TAG:-}" ]]; then
        log_info "No Travis tag found - running unit tests only"
        bash release.sh test all all 0.1
        return 0
    fi
    
    local success=true
    
    # Authenticate with Docker Hub
    docker_login
    
    # Execute builds based on environment variables
    if [[ -n "${ANDROID_VERSION:-}" ]]; then
        if ! execute_android_build "$ANDROID_VERSION" "$TRAVIS_TAG"; then
            success=false
        fi
    elif [[ -n "${REAL_DEVICE:-}" ]]; then
        if ! execute_real_device_build "$TRAVIS_TAG"; then
            success=false
        fi
    elif [[ -n "${GENYMOTION:-}" ]]; then
        if ! execute_genymotion_build "$TRAVIS_TAG"; then
            success=false
        fi
    else
        log_info "No specific build type specified - skipping build"
    fi
    
    # Always logout, even if build failed
    docker_logout
    
    # Exit with appropriate code
    if [[ "$success" != "true" ]]; then
        log_error "Build process failed"
        exit 1
    fi
    
    log_info "Build process completed successfully"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

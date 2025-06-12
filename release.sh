#!/bin/bash
# Bash version should >= 4 to be able to run this script.
set -euo pipefail  # Strict mode: exit on error, exit on undefined variable, exit on pipe failure

# Constants definition
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly IMAGE="${DOCKER_ORG:-rcswain}/docker-android"
readonly DEFAULT_PROCESSOR="x86_64"

# Get API level for Android version
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

# Get ChromeDriver version for Android version
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

# Check if Android version is supported
is_supported_version() {
    local api_level
    api_level=$(get_api_level "$1")
    [[ -n "$api_level" ]]
}

# Global variables
TASK=""
ANDROID_VERSION=""
RELEASE=""
ANDROID_VERSIONS=()

# Logging functions
log_info() {
    echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_build() {
    echo "[BUILD] $*" >&2
}

log_push() {
    echo "[PUSH] $*" >&2
}

# Get supported versions string
get_supported_versions_string() {
    echo "5.0.1|5.1.1|6.0|7.0|7.1.1|8.0|8.1|9.0|10.0|11.0|12.0|13.0|14.0|15.0|16.0"
}

# Show usage help
show_usage() {
    cat << EOF
Usage: $0 [TASK] [ANDROID_VERSION] [RELEASE]

Parameters:
  TASK             Task to execute: test|build|push|all
  ANDROID_VERSION  Android version: $(get_supported_versions_string) or 'all'
  RELEASE          Release version string

Examples:
  $0 build 7.1.1 v1.0.0
  $0 all all latest
  $0 test
EOF
}

# Validate input parameters
validate_input() {
    # Validate task type
    case "$TASK" in
        test|build|push|all) ;;
        *)
            log_error "Invalid task: $TASK"
            show_usage
            exit 1
            ;;
    esac

    # Validate Android version
    if [[ "$ANDROID_VERSION" != "all" ]] && ! is_supported_version "$ANDROID_VERSION"; then
        log_error "Unsupported Android version: $ANDROID_VERSION"
        log_error "Supported versions: $(get_supported_versions_string)"
        exit 1
    fi

    # Validate release version
    if [[ -z "$RELEASE" ]]; then
        log_error "Release version cannot be empty"
        exit 1
    fi
}

# Get user input
get_user_input() {
    if [[ -z "$1" ]]; then
        read -p "Task (test|build|push|all): " TASK
    else
        TASK="$1"
    fi

    if [[ -z "${2:-}" ]]; then
        read -p "Android version ($(get_supported_versions_string)|all): " ANDROID_VERSION
    else
        ANDROID_VERSION="$2"
    fi

    if [[ -z "${3:-}" ]]; then
        read -p "Release version: " RELEASE
    else
        RELEASE="$3"
    fi
}

# Parse Android versions list
parse_android_versions() {
    if [[ "$ANDROID_VERSION" == "all" ]]; then
        ANDROID_VERSIONS=(5.0.1 5.1.1 6.0 7.0 7.1.1 8.0 8.1 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0)
    else
        ANDROID_VERSIONS=("$ANDROID_VERSION")
    fi

    log_info "Target Android versions: ${ANDROID_VERSIONS[*]}"
}

# Get image type
get_img_type() {
    case "$1" in
        5.0.1|5.1.1) echo "default" ;;
        *) echo "google_apis" ;;
    esac
}

# Get browser type
get_browser() {
    case "$1" in
        5.0.1|5.1.1|6.0) echo "browser" ;;
        *) echo "chrome" ;;
    esac
}

# Get processor type
get_processor() {
    case "$1" in
        9.0) echo "x86_64" ;;
        *) echo "$DEFAULT_PROCESSOR" ;;
    esac
}

# Get system image type  
get_sys_img() {
    case "$1" in
        8.1) echo "x86" ;;
        9.0) echo "x86_64" ;;
        *) echo "$DEFAULT_PROCESSOR" ;;
    esac
}

# Wait for container health check
wait_for_container_healthy() {
    local container_name="$1"
    local max_attempts="${2:-10}"
    local attempt=0

    log_info "Waiting for container $container_name to be healthy..."

    while [[ $attempt -le $max_attempts ]]; do
        ((attempt++))
        
        if docker ps --filter "name=$container_name" --filter "health=healthy" --format "table {{.Names}}" | grep -q "$container_name"; then
            log_info "Container $container_name is healthy"
            return 0
        fi

        log_info "Attempt $attempt/$max_attempts: waiting 10 seconds..."
        sleep 10
    done

    log_error "Container $container_name failed to become healthy after $max_attempts attempts"
    return 1
}

# Clean up Docker resources
cleanup_docker_resources() {
    local container_name="$1"
    
    if docker ps -a --format "table {{.Names}}" | grep -q "$container_name"; then
        log_info "Removing container: $container_name"
        docker kill "$container_name" 2>/dev/null || true
        docker rm "$container_name" 2>/dev/null || true
    fi
}

# Run E2E tests
run_e2e_tests() {
    # Test configuration
    local -r test_android_version="7.1.1"
    local -r test_api_level="25"
    local -r test_processor="x86"
    local -r test_img_type="google_apis"
    local -r test_browser="chrome"
    local -r test_image="test_img"
    local -r test_container="test_con"

    # Only run E2E tests on Linux x86 environment
    if [[ "$(uname -s)" != "Linux" ]] || [[ "${E2E:-}" != "true" ]]; then
        log_info "Skipping E2E tests (not Linux or E2E not enabled)"
        return 0
    fi

    log_info "Building test image..."
    docker build -t "$test_image" \
        --build-arg ANDROID_VERSION="$test_android_version" \
        --build-arg API_LEVEL="$test_api_level" \
        --build-arg PROCESSOR="$test_processor" \
        --build-arg SYS_IMG="$test_processor" \
        --build-arg IMG_TYPE="$test_img_type" \
        --build-arg BROWSER="$test_browser" \
        -f docker/Emulator_x86 .

    # Clean up old containers
    cleanup_docker_resources "$test_container"

    log_info "Starting test container..."
    docker run --privileged -d \
        -p 4723:4723 -p 6080:6080 \
        -e APPIUM=True \
        -e DEVICE="Samsung Galaxy S6" \
        --name "$test_container" \
        "$test_image"

    docker cp example/sample_apk "$test_container:/root/tmp"

    # Wait for container to be ready
    if ! wait_for_container_healthy "$test_container"; then
        cleanup_docker_resources "$test_container"
        exit 1
    fi

    log_info "Running E2E tests..."
    if ! python -m pytest src/tests/e2e -v --tb=short --cov=src --cov-report=xml:coverage_e2e.xml; then
        log_error "E2E tests failed"
        cleanup_docker_resources "$test_container"
        exit 1
    fi

    cleanup_docker_resources "$test_container"
}

# Run unit tests
run_unit_tests() {
    local -r test_android_version="7.1.1"
    local -r test_api_level="25"
    local -r test_processor="x86"
    local -r test_img_type="google_apis"

    log_info "Running unit tests..."
    (
        export ANDROID_HOME=/root
        export ANDROID_VERSION="$test_android_version"
        export API_LEVEL="$test_api_level"
        export PROCESSOR="$test_processor"
        export SYS_IMG="$test_processor"
        export IMG_TYPE="$test_img_type"
        
        python -m pytest src/tests/unit -v --tb=short --cov=src --cov-report=xml:coverage_unit.xml --cov-report=html:coverage
    )
}

# Execute tests
execute_tests() {
    run_e2e_tests
    run_unit_tests
    log_info "All tests completed successfully"
}

# Build Docker image
build_docker_image() {
    local version="$1"
    local api_level
    local chrome_driver
    local img_type
    local browser
    local processor
    local sys_img
    
    api_level=$(get_api_level "$version")
    chrome_driver=$(get_chromedriver_version "$version")
    img_type=$(get_img_type "$version")
    browser=$(get_browser "$version")
    processor=$(get_processor "$version")
    sys_img=$(get_sys_img "$version")
    
    local image_version="$IMAGE-x86-$version:$RELEASE"
    local image_latest="$IMAGE-x86-$version:latest"
    local dockerfile="${DOCKERFILE:-docker/Emulator_x86}"
    
    # Use optimized version if available
    if [[ -f "docker/Emulator_x86.optimized" ]] && [[ "${USE_OPTIMIZED:-}" == "true" ]]; then
        dockerfile="docker/Emulator_x86.optimized"
        log_build "Using optimized Dockerfile for smaller image size"
    fi

    log_build "Building image for Android $version"
    log_build "API Level: $api_level"
    log_build "Image Type: $img_type"
    log_build "System Image: $sys_img"
    log_build "ChromeDriver version: $chrome_driver"
    log_build "Image names: $image_version, $image_latest"
    log_build "Dockerfile: $dockerfile"

    # Build image
    docker build -t "$image_version" \
        ${TOKEN:+--build-arg TOKEN="$TOKEN"} \
        --build-arg ANDROID_VERSION="$version" \
        --build-arg API_LEVEL="$api_level" \
        --build-arg PROCESSOR="$processor" \
        --build-arg SYS_IMG="$sys_img" \
        --build-arg IMG_TYPE="$img_type" \
        --build-arg BROWSER="$browser" \
        --build-arg CHROME_DRIVER="$chrome_driver" \
        --build-arg APP_RELEASE_VERSION="$RELEASE" \
        -f "$dockerfile" .

    # Tag as latest
    docker tag "$image_version" "$image_latest"
    log_build "Successfully built $image_version"
}

# Execute build
execute_build() {
    log_info "Cleaning up Python cache files..."
    find . -name "*.pyc" -delete 2>/dev/null || true

    log_info "Building Docker images..."
    for version in "${ANDROID_VERSIONS[@]}"; do
        build_docker_image "$version"
    done
    
    log_info "All images built successfully"
}

# Push Docker image
push_docker_image() {
    local version="$1"
    local image_version="$IMAGE-x86-$version:$RELEASE"
    local image_latest="$IMAGE-x86-$version:latest"

    log_push "Pushing $image_version"
    if ! docker push "$image_version"; then
        log_error "Failed to push $image_version"
        return 1
    fi

    log_push "Pushing $image_latest"
    if ! docker push "$image_latest"; then
        log_error "Failed to push $image_latest"
        return 1
    fi

    log_push "Successfully pushed images for Android $version"
}

# Execute push
execute_push() {
    log_info "Pushing Docker images..."
    for version in "${ANDROID_VERSIONS[@]}"; do
        push_docker_image "$version"
    done
    log_info "All images pushed successfully"
}

# Main function
main() {
    # Get parameters
    get_user_input "$@"
    
    # Validate input
    validate_input
    
    # Parse version list
    parse_android_versions

    # Execute task
    case "$TASK" in
        test)
            execute_tests
            ;;
        build)
            execute_build
            ;;
        push)
            execute_push
            ;;
        all)
            execute_tests
            execute_build
            execute_push
            ;;
    esac

    log_info "Task '$TASK' completed successfully"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

#!/bin/bash
# Bash version should >= 4 to be able to run this script.
set -euo pipefail  # Strict mode: exit on error, exit on undefined variable, exit on pipe failure

# Constants definition
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly IMAGE="${DOCKER_ORG:-rcswain}/docker-android"
readonly DEFAULT_PROCESSOR="x86_64"

# Supported Android versions and API level mapping
# https://apilevels.com/
declare -A readonly ANDROID_API_LEVELS=(
    [5.0.1]=21
    [5.1.1]=22
    [6.0]=23
    [7.0]=24
    [7.1.1]=25
    [8.0]=26
    [8.1]=27
    [9.0]=28
    [10.0]=29
    [11.0]=30
    [12.0]=31
    [13.0]=33
    [14.0]=34
    [15.0]=35
    [16.0]=36
)


# ChromeDriver version mapping
# "Chrome for Testing availability" https://googlechromelabs.github.io/chrome-for-testing/
declare -A readonly CHROMEDRIVER_VERSIONS=(
    [5.0.1]="2.21"
    [5.1.1]="2.13"
    [6.0]="2.18"
    [7.0]="2.23"
    [7.1.1]="2.28"
    [8.0]="2.31"
    [8.1]="2.33"
    [9.0]="2.40"
    [10.0]="74.0.3729.6"
    [11.0]="83.0.4103.39"
    [12.0]="92.0.4515.43"
    [13.0]="104.0.5112.29"
    [14.0]="114.0.5735.90"
    [15.0]="114.0.5735.90"
    [16.0]="137.0.7151.70"
)

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

# Get supported versions string
get_supported_versions_string() {
    local versions=()
    for version in "${!ANDROID_API_LEVELS[@]}"; do
        versions+=("$version")
    done
    printf "%s|" "${versions[@]}" | sed 's/|$//'
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
    if [[ "$ANDROID_VERSION" != "all" ]] && [[ -z "${ANDROID_API_LEVELS[$ANDROID_VERSION]:-}" ]]; then
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
        for version in "${!ANDROID_API_LEVELS[@]}"; do
            ANDROID_VERSIONS+=("$version")
        done
    else
        ANDROID_VERSIONS=("$ANDROID_VERSION")
    fi

    log_info "Target Android versions: ${ANDROID_VERSIONS[*]}"
}

# Get image configuration
get_image_config() {
    local version="$1"
    local -n config_ref=$2
    
    # Set default values
    config_ref[img_type]="google_apis"
    config_ref[browser]="chrome"
    config_ref[processor]="$DEFAULT_PROCESSOR"
    config_ref[sys_img]="$DEFAULT_PROCESSOR"

    # Adjust configuration based on version
    case "$version" in
        5.0.1|5.1.1)
            config_ref[img_type]="default"
            config_ref[browser]="browser"
            ;;
        6.0)
            config_ref[img_type]="google_apis"
            config_ref[browser]="browser"
            ;;
        8.1)
            config_ref[sys_img]="x86"
            ;;
        9.0)
            config_ref[processor]="x86_64"
            ;;
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
    local -A config
    
    get_image_config "$version" config
    
    local api_level="${ANDROID_API_LEVELS[$version]}"
    local chrome_driver="${CHROMEDRIVER_VERSIONS[$version]}"
    local image_version="$IMAGE-x86-$version:$RELEASE"
    local image_latest="$IMAGE-x86-$version:latest"
    local dockerfile="docker/Emulator_x86"

    log_build "Building image for Android $version"
    log_build "API Level: $api_level"
    log_build "Image Type: ${config[img_type]}"
    log_build "System Image: ${config[sys_img]}"
    log_build "ChromeDriver version: $chrome_driver"
    log_build "Image names: $image_version, $image_latest"
    log_build "Dockerfile: $dockerfile"

    # Build image
    docker build -t "$image_version" \
        ${TOKEN:+--build-arg TOKEN="$TOKEN"} \
        --build-arg ANDROID_VERSION="$version" \
        --build-arg API_LEVEL="$api_level" \
        --build-arg PROCESSOR="${config[processor]}" \
        --build-arg SYS_IMG="${config[sys_img]}" \
        --build-arg IMG_TYPE="${config[img_type]}" \
        --build-arg BROWSER="${config[browser]}" \
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

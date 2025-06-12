#!/bin/bash
# Android SDK optimization script
# This script removes unnecessary SDK components to reduce image size

set -euo pipefail

readonly ANDROID_HOME="${ANDROID_HOME:-/root}"
readonly API_LEVEL="${API_LEVEL:-27}"
readonly SYS_IMG="${SYS_IMG:-x86_64}"
readonly IMG_TYPE="${IMG_TYPE:-google_apis}"

log_info() {
    echo "[OPTIMIZE] $*" >&2
}

# Remove unnecessary SDK components
optimize_sdk() {
    local sdk_root="$ANDROID_HOME"
    
    log_info "Starting Android SDK optimization..."
    
    # Remove build-tools except the latest one
    if [[ -d "$sdk_root/build-tools" ]]; then
        log_info "Cleaning up old build-tools..."
        cd "$sdk_root/build-tools"
        # Keep only the latest version directory
        ls -1 | head -n -1 | xargs -r rm -rf
        cd - > /dev/null
    fi
    
    # Remove platforms except the target API level
    if [[ -d "$sdk_root/platforms" ]]; then
        log_info "Removing unnecessary platform versions..."
        cd "$sdk_root/platforms"
        for dir in android-*; do
            if [[ "$dir" != "android-${API_LEVEL}" ]] && [[ -d "$dir" ]]; then
                rm -rf "$dir"
                log_info "Removed platform: $dir"
            fi
        done
        cd - > /dev/null
    fi
    
    # Remove unnecessary system images
    if [[ -d "$sdk_root/system-images" ]]; then
        log_info "Cleaning up system images..."
        find "$sdk_root/system-images" -type d -name "android-*" | while read -r img_dir; do
            local api_version
            api_version=$(basename "$img_dir" | sed 's/android-//')
            if [[ "$api_version" != "$API_LEVEL" ]]; then
                rm -rf "$img_dir"
                log_info "Removed system image for API $api_version"
            fi
        done
        
        # Within the target API, remove unnecessary image types
        local target_img_dir="$sdk_root/system-images/android-${API_LEVEL}"
        if [[ -d "$target_img_dir" ]]; then
            cd "$target_img_dir"
            for img_type_dir in *; do
                if [[ "$img_type_dir" != "$IMG_TYPE" ]] && [[ -d "$img_type_dir" ]]; then
                    rm -rf "$img_type_dir"
                    log_info "Removed image type: $img_type_dir"
                fi
            done
            
            # Remove unnecessary architectures
            if [[ -d "$IMG_TYPE" ]]; then
                cd "$IMG_TYPE"
                for arch_dir in *; do
                    if [[ "$arch_dir" != "$SYS_IMG" ]] && [[ -d "$arch_dir" ]]; then
                        rm -rf "$arch_dir"
                        log_info "Removed architecture: $arch_dir"
                    fi
                done
                cd - > /dev/null
            fi
            cd - > /dev/null
        fi
    fi
    
    # Remove unnecessary emulator snapshots and temporary files
    log_info "Cleaning emulator cache and temporary files..."
    find "$sdk_root" -type f -name "*.log" -delete 2>/dev/null || true
    find "$sdk_root" -type f -name "*.tmp" -delete 2>/dev/null || true
    find "$sdk_root" -type f -name "core.*" -delete 2>/dev/null || true
    
    # Remove emulator test data
    rm -rf "$sdk_root/emulator/testdata" 2>/dev/null || true
    rm -rf "$sdk_root/emulator/lib/qt/bin/test*" 2>/dev/null || true
    
    # Remove documentation and examples
    rm -rf "$sdk_root/docs" 2>/dev/null || true
    rm -rf "$sdk_root/samples" 2>/dev/null || true
    
    # Remove unnecessary tools
    local tools_to_remove=(
        "tools/bin/uiautomatorviewer"
        "tools/bin/jobb"
        "tools/bin/lint"
        "tools/bin/screenshot2"
        "tools/bin/dmtracedump"
        "tools/bin/hprof-conv"
        "tools/bin/etc1tool"
    )
    
    for tool in "${tools_to_remove[@]}"; do
        rm -f "$sdk_root/$tool" 2>/dev/null || true
    done
    
    # Compress large static files if possible
    log_info "Compressing static resources..."
    find "$sdk_root" -name "*.jar" -size +10M -exec gzip -9 {} \; 2>/dev/null || true
    
    log_info "SDK optimization completed"
}

# Clean package manager caches
clean_package_caches() {
    log_info "Cleaning package manager caches..."
    
    # APT cleanup
    apt-get autoremove -y 2>/dev/null || true
    apt-get autoclean 2>/dev/null || true
    apt-get clean 2>/dev/null || true
    
    # Remove cache directories
    rm -rf /var/lib/apt/lists/* \
           /var/cache/apt/archives/* \
           /tmp/* \
           /var/tmp/* \
           /root/.cache \
           /root/.wget-hsts \
           2>/dev/null || true
    
    # Remove unnecessary documentation
    rm -rf /usr/share/doc/* \
           /usr/share/man/* \
           /usr/share/info/* \
           /usr/share/locale/* \
           2>/dev/null || true
           
    log_info "Package cache cleanup completed"
}

# Show disk usage before and after
show_usage() {
    local label="$1"
    log_info "$label disk usage:"
    df -h / | tail -1
    if [[ -d "$ANDROID_HOME" ]]; then
        du -sh "$ANDROID_HOME" | cut -f1 | xargs -I {} log_info "Android SDK size: {}"
    fi
}

main() {
    show_usage "Before optimization"
    optimize_sdk
    clean_package_caches
    show_usage "After optimization"
}

# Run optimization if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 
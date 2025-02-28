#!/bin/bash

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Cache and failures files
CACHE_FILE=".checksum_cache.json"
FAILURES_FILE=".checksum_failures.txt"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Initialize or load cache
if [[ ! -f "$CACHE_FILE" ]]; then
    echo "{}" > "$CACHE_FILE"
fi

# Remove previous failures file if it exists
if [[ -f "$FAILURES_FILE" ]]; then
    rm -f "$FAILURES_FILE"
fi

# Function to get file metadata
get_file_metadata() {
    local filename=$1
    local mtime=$(stat -c %Y "$filename" 2>/dev/null || stat -f %m "$filename")
    local size=$(stat -c %s "$filename" 2>/dev/null || stat -f %z "$filename")
    echo "$mtime:$size"
}

# Function to get cached checksum
get_cached_checksum() {
    local filename=$1
    local metadata=$2
    local cache_entry
    
    if ! cache_entry=$(jq -r ".[\"$filename\"] // empty" "$CACHE_FILE"); then
        return 1
    fi
    
    if [[ -n "$cache_entry" ]]; then
        local cached_metadata
        cached_metadata=$(echo "$cache_entry" | jq -r '.metadata')
        if [[ "$cached_metadata" == "$metadata" ]]; then
            echo "$cache_entry" | jq -r '.checksum'
            return 0
        fi
    fi
    return 1
}

# Function to update cache
update_cache() {
    local filename=$1
    local checksum=$2
    local metadata=$3
    local tmp_cache
    
    tmp_cache=$(mktemp)
    jq --arg fn "$filename" \
       --arg cs "$checksum" \
       --arg md "$metadata" \
       '.[$fn] = {"checksum": $cs, "metadata": $md}' "$CACHE_FILE" > "$tmp_cache"
    mv "$tmp_cache" "$CACHE_FILE"
}

# Read input arguments
num_files=$1
checksums=(${2//,/ })  # Split the comma-separated checksums into an array
filenames=(${3//,/ })  # Split the comma-separated filenames into an array

# Validate the number of arguments
if [[ $# -lt 3 ]]; then
    log "ERROR: Insufficient arguments."
    echo "Usage: $0 <num_files> <comma-separated-checksums> <comma-separated-filenames>"
    exit 1
fi

# Ensure checksums and filenames arrays match in size
if [[ ${#checksums[@]} -ne ${#filenames[@]} ]]; then
    log "ERROR: Number of checksums does not match number of filenames."
    exit 1
fi

log "Starting checksum validation for $num_files files"
num_threads=$(nproc)
log "Number of CPU threads: $num_threads"

# Function to validate a single file
validate_file() {
    local filename=$1
    local expected_checksum=$2
    local index=$3
    local result_file="$TEMP_DIR/result_$index"
    local metadata
    local cached_checksum
    local computed_checksum
    
    metadata=$(get_file_metadata "$filename")
    cached_checksum=$(get_cached_checksum "$filename" "$metadata")
    
    if [[ -n "$cached_checksum" ]]; then
        log "Using cached checksum for $filename"
        computed_checksum="$cached_checksum"
    else
        log "Computing checksum for $filename"
        computed_checksum=$(sha256sum "$filename" | awk '{print $1}')
        update_cache "$filename" "$computed_checksum" "$metadata"
    fi
    
    if [[ "$computed_checksum" != "$expected_checksum" ]]; then
        echo "ERROR|$filename|$expected_checksum|$computed_checksum" > "$result_file"
    else
        echo "SUCCESS|$filename|$computed_checksum" > "$result_file"
    fi
}

# Export functions and variables needed by parallel processes
export -f validate_file
export -f log
export -f get_file_metadata
export -f get_cached_checksum
export -f update_cache
export TEMP_DIR
export CACHE_FILE

# Process files in parallel using GNU Parallel
if command -v parallel >/dev/null 2>&1; then
    log "Using GNU Parallel for processing"
    parallel --halt now,fail=1 validate_file {1} {2} {#} ::: "${filenames[@]}" ::: "${checksums[@]}"
else
    # Fallback to background processes if GNU Parallel is not available
    log "GNU Parallel not found, using background processes"
    for (( i = 0; i < num_files; i++ )); do
        validate_file "${filenames[$i]}" "${checksums[$i]}" "$i" &
        
        # Limit the number of concurrent processes
        if (( (i + 1) % num_threads == 0 )); then
            wait
        fi
    done
    wait
fi

# Process results and collect validated checksums
failed=0
declare -a validated_entries
declare -a failed_entries
for (( i = 0; i < num_files; i++ )); do
    result_file="$TEMP_DIR/result_$i"
    if [[ -f "$result_file" ]]; then
        IFS='|' read -r status filename checksum1 checksum2 < "$result_file"
        
        if [[ "$status" == "ERROR" ]]; then
            log "ERROR: Checksum validation failed for $filename"
            log "Expected: $checksum1"
            log "Computed: $checksum2"
            failed=1
            # Delete the failed file and store its info
            rm -f "$filename"
            echo "$filename|$checksum1" >> "$FAILURES_FILE"
            failed_entries+=("$filename")
            log "Deleted failed file: $filename"
        else
            log "Checksum validation successful for $filename"
            validated_entries+=("$filename: $checksum1")
        fi
    fi
done

# Only create validation file if all checksums passed
if [[ $failed -eq 0 ]]; then
    # All checksums are valid
    log "All checksums validated successfully"
    log "Validation details stored in cache file: $CACHE_FILE"
    exit 0
else
    log "Checksum validation failed for ${#failed_entries[@]} files"
    log "Failed files written to $FAILURES_FILE"
    # Exit with code 2 to indicate checksum failures (different from other errors)
    exit 2
fi

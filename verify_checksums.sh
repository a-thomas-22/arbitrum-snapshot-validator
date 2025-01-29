#!/bin/bash

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Validation flag file with detailed checksum information
VALIDATION_FILE=".checksums_validated"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Exit if validation file already exists
if [[ -f "$VALIDATION_FILE" ]]; then
    log "Validation file $VALIDATION_FILE already exists. Exiting."
    exit 1
fi

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
    
    computed_checksum=$(sha256sum "$filename" | awk '{print $1}')
    
    if [[ "$computed_checksum" != "$expected_checksum" ]]; then
        echo "ERROR|$filename|$expected_checksum|$computed_checksum" > "$result_file"
    else
        echo "SUCCESS|$filename|$computed_checksum" > "$result_file"
    fi
}

# Export functions and variables needed by parallel processes
export -f validate_file
export -f log
export TEMP_DIR

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
for (( i = 0; i < num_files; i++ )); do
    result_file="$TEMP_DIR/result_$i"
    if [[ -f "$result_file" ]]; then
        IFS='|' read -r status filename checksum1 checksum2 < "$result_file"
        
        if [[ "$status" == "ERROR" ]]; then
            log "ERROR: Checksum validation failed for $filename"
            log "Expected: $checksum1"
            log "Computed: $checksum2"
            failed=1
            break
        else
            log "Checksum validation successful for $filename"
            validated_entries+=("$filename: $checksum1")
        fi
    fi
done

# Only create validation file if all checksums passed
if [[ $failed -eq 0 ]]; then
    # Create validation file and write all entries at once
    printf "%s\n" "${validated_entries[@]}" > "$VALIDATION_FILE"
    log "All checksums validated successfully"
    log "Validation details written to $VALIDATION_FILE"
    exit 0
else
    exit 1
fi

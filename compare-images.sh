#!/usr/bin/env bash

set -euo pipefail

# Docker image names
BASELINE="epicbook-backend:baseline"
OPTIMIZED="epicbook-backend:1.0"
FRONTEND="epicbook-frontend:1.0"

# Get image sizes in bytes
get_size() {
    docker image inspect "$1" \
        --format '{{.Size}}' 2>/dev/null ||
    {
        echo "Error: Image '$1' not found." >&2
        exit 1
    }
}

BASELINE_BYTES=$(get_size "$BASELINE")
OPTIMIZED_BYTES=$(get_size "$OPTIMIZED")
FRONTEND_BYTES=$(get_size "$FRONTEND")

echo
echo "************ Epicbook Docker Images ************"
docker images | grep epicbook

# Convert bytes to MB for reporting
to_mb() {
    awk -v bytes="$1" 'BEGIN { printf "%.2f MB", bytes / 1000000 }'
}

# Calculate image-size reduction percentage
REDUCTION=$(awk \
    -v baseline="$BASELINE_BYTES" \
    -v optimized="$OPTIMIZED_BYTES" \
    'BEGIN {
        if (baseline <= 0) {
            print "N/A"
        } else {
            printf "%.2f%%", \
                ((baseline - optimized) / baseline) * 100
        }
    }')

# Print report
echo
echo "=========================================================="
echo "  Backend Baseline and Optimized Docker Image Size Report"
echo "=========================================================="
printf "%-25s %15s\n" "Image" "Size"
printf "%-25s %15s\n" "-------------------------" "---------------"
printf "%-25s %15s\n" "Baseline backend" "$(to_mb "$BASELINE_BYTES")"
printf "%-25s %15s\n" "Optimized backend" "$(to_mb "$OPTIMIZED_BYTES")"

echo "--------------------------------------"
echo "Backend image-size reduction: $REDUCTION"
echo "======================================"
echo

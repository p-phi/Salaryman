#!/usr/bin/env bash
set -euo pipefail

# Get the current time in the format: HH:MM:SS
hostname=$(hostname)

# Output the result
echo '{"hostname": "'$hostname'", "message": "Current hostname retrieved successfully."}'

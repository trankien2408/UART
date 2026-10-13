#!/usr/bin/env bash
set -euo pipefail
firmware_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$firmware_dir/../fpga/scripts/env.sh"
exec juart-terminal "$@"

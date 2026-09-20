#!/usr/bin/env bash
# ==============================================================================
# Main Orchestrator Entrypoint (Transition wrapper for Phase 1)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/run_all_onclick.sh" "$@"

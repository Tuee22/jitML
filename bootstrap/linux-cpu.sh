#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=bootstrap/_lib.sh
source "$script_dir/_lib.sh"

substrate="linux-cpu"

print_help() {
  cat <<'EOF'
Usage: bootstrap/linux-cpu.sh <command>

Stage-0 contract:
  Checks Docker is usable by the current user without sudo only.
  Delegates: docker compose run --rm jitml jitml bootstrap --linux-cpu

Commands:
  help      Print this help.
  doctor    Check the Linux CPU stage-0 host gates.
  build     Build the jitml:local image.
  up        Delegate to the Haskell bootstrap inside the outer container.
  status    Print local stack status from ./.build/runtime/cluster-publication.json.
  test      Run the canonical jitML test surface in the outer container.
  down      Tear the local stack down while preserving state.
  purge     Remove runtime state; --full also removes build artifacts.
EOF
}

doctor() {
  require_docker_without_sudo
  info "$substrate stage-0 doctor: ok"
}

up() {
  doctor
  run_linux_compose_bootstrap "$substrate" "$@"
}

main() {
  while [ "${1:-}" = "--command-dir" ]; do
    bootstrap_command_dir=${2:-}
    if [ -z "$bootstrap_command_dir" ]; then
      die 64 "missing value for --command-dir"
    fi
    shift 2
  done
  local command_name=${1:-help}
  shift || true
  case "$command_name" in
    help|-h|--help)
      print_help
      ;;
    doctor)
      doctor "$@"
      ;;
    build)
      build_linux_image
      ;;
    up)
      up "$@"
      ;;
    status)
      print_cluster_status "$substrate"
      ;;
    test)
      run_linux_compose_jitml test all "$@"
      ;;
    down)
      kind_down "$substrate"
      ;;
    purge)
      full=false
      if [ "${1:-}" = "--full" ]; then
        full=true
      fi
      purge_linux_state "$substrate" "$full"
      ;;
    *)
      die 64 "unknown linux-cpu bootstrap command: $command_name"
      ;;
  esac
}

main "$@"

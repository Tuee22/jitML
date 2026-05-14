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
  build     Build the jitml:local image (Sprint 2.4).
  up        Delegate to the Haskell bootstrap inside the outer container.
  status    Print local stack status (Sprint 2.6).
  test      Run the canonical jitML test surface (Sprint 2.6).
  down      Tear the local stack down while preserving state (Sprint 2.7).
  purge     Remove runtime state; --full also removes build artifacts (Sprint 2.7).
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
      phase_later "$substrate $command_name" "Sprint 2.4"
      ;;
    up)
      up "$@"
      ;;
    status|test)
      phase_later "$substrate $command_name" "Sprint 2.6"
      ;;
    down|purge)
      phase_later "$substrate $command_name" "Sprint 2.7"
      ;;
    *)
      die 64 "unknown linux-cpu bootstrap command: $command_name"
      ;;
  esac
}

main "$@"

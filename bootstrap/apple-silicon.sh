#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=bootstrap/_lib.sh
source "$script_dir/_lib.sh"

substrate="apple-silicon"

print_help() {
  cat <<'EOF'
Usage: bootstrap/apple-silicon.sh <command>

Stage-0 contract:
  Checks macOS on Apple Silicon, Xcode Command Line Tools, and Homebrew only.
  Delegates: ./.build/jitml bootstrap --apple-silicon

Commands:
  help        Print this help.
  doctor      Check the Apple Silicon stage-0 host gates.
  build       Build ./.build/jitml host-native.
  up          Build ./.build/jitml and delegate to the Haskell bootstrap.
  run-daemon  Run the host-native jitml service daemon in the foreground
              (long-running; required for Metal inference after 'up').
  status      Print local stack status from ./.build/runtime/cluster-publication.json.
  test        Run the canonical jitML test surface.
  down        Tear the local stack down while preserving state.
  purge       Remove runtime state; --full also removes build artifacts.
EOF
}

doctor() {
  require_macos_arm64
  require_xcode_command_line_tools
  require_homebrew
  info "$substrate stage-0 doctor: ok"
}

build() {
  doctor
  build_host_jitml
}

up() {
  build
  prepull_apple_third_party_images
  run_apple_bootstrap "$@"
}

run_daemon() {
  build
  local host_config="$script_dir/../.build/conf/host/apple-silicon.dhall"
  if [ ! -f "$host_config" ]; then
    die 3 "host config missing at $host_config; run bootstrap/apple-silicon.sh up first"
  fi
  info "starting host-native jitml service (Ctrl-C to stop)"
  exec "$script_dir/../.build/jitml" service --config "$host_config" "$@"
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
      build "$@"
      ;;
    up)
      up "$@"
      ;;
    run-daemon)
      run_daemon "$@"
      ;;
    status)
      print_cluster_status "$substrate"
      ;;
    test)
      build
      "$script_dir/../.build/jitml" test all --apple-silicon "$@"
      ;;
    down)
      kind_down "$substrate"
      ;;
    purge)
      full=false
      if [ "${1:-}" = "--full" ]; then
        full=true
      fi
      purge_state "$substrate" "$full"
      ;;
    *)
      die 64 "unknown apple-silicon bootstrap command: $command_name"
      ;;
  esac
}

main "$@"

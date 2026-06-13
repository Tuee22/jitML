#!/usr/bin/env bash
set -euo pipefail

bootstrap_component="bootstrap"
cuda_min_compute_capability=7.0
bootstrap_command_dir=""

json_escape() {
  local value=${1:-}
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  printf '%s' "$value"
}

log_json() {
  local level=$1
  local message=$2
  printf '{"level":"%s","component":"%s","message":"%s"}\n' \
    "$(json_escape "$level")" \
    "$(json_escape "$bootstrap_component")" \
    "$(json_escape "$message")" >&2
}

info() {
  log_json "info" "$1"
}

warn() {
  log_json "warn" "$1"
}

die() {
  local code=$1
  local message=$2
  log_json "error" "$message"
  exit "$code"
}

have() {
  command_path "$1" >/dev/null 2>&1
}

command_path() {
  local command_name=$1
  if [ -n "$bootstrap_command_dir" ]; then
    if [ -x "$bootstrap_command_dir/$command_name" ]; then
      printf '%s\n' "$bootstrap_command_dir/$command_name"
      return 0
    fi
    return 127
  fi
  command -v "$command_name"
}

run_command() {
  local command_name=$1
  shift || true
  local resolved
  resolved=$(command_path "$command_name") || return 127
  "$resolved" "$@"
}

repo_root() {
  local script_dir
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  cd "$script_dir/.." && pwd
}

host_uname_s() {
  run_command uname -s
}

host_uname_m() {
  run_command uname -m
}

require_command() {
  local command_name=$1
  local remedy=$2
  if ! have "$command_name"; then
    die 2 "missing required command '$command_name'; $remedy"
  fi
}

require_macos_arm64() {
  local os_name
  local arch_name
  os_name=$(host_uname_s)
  arch_name=$(host_uname_m)
  if [ "$os_name" != "Darwin" ]; then
    die 2 "apple-silicon bootstrap requires macOS; detected '$os_name'"
  fi
  if [ "$arch_name" != "arm64" ]; then
    die 2 "apple-silicon bootstrap requires Apple Silicon arm64; detected '$arch_name'"
  fi
}

require_xcode_command_line_tools() {
  require_command "xcode-select" "install Xcode Command Line Tools with 'xcode-select --install'"
  if ! run_command xcode-select -p >/dev/null 2>&1; then
    die 2 "Xcode Command Line Tools are not selected; run 'xcode-select --install'"
  fi
}

require_homebrew() {
  require_command "brew" "install Homebrew from https://brew.sh/"
  if ! run_command brew --version >/dev/null 2>&1; then
    die 2 "Homebrew is installed but not runnable; repair Homebrew before bootstrapping"
  fi
}

require_docker_without_sudo() {
  require_command "docker" "install Docker and make it usable by the current user"
  if ! run_command docker info >/dev/null 2>&1; then
    die 2 "Docker must be usable by the current user without sudo; start Docker or add this user to the docker group"
  fi
}

require_nvidia_container_runtime() {
  local runtimes
  if ! runtimes=$(run_command docker info --format '{{json .Runtimes}}' 2>/dev/null); then
    die 2 "cannot inspect Docker runtimes; ensure Docker is running without sudo"
  fi
  case "$runtimes" in
    *nvidia*) ;;
    *)
      die 2 "NVIDIA container runtime is not registered with Docker; install and configure nvidia-container-toolkit"
      ;;
  esac
}

compute_capability_at_least() {
  local actual=$1
  local required=$2
  local actual_major=${actual%%.*}
  local actual_minor=${actual#*.}
  local required_major=${required%%.*}
  local required_minor=${required#*.}
  if [ "$actual_minor" = "$actual" ]; then
    actual_minor=0
  fi
  if [ "$required_minor" = "$required" ]; then
    required_minor=0
  fi
  case "$actual_major$actual_minor$required_major$required_minor" in
    *[!0-9]* | "") return 1 ;;
  esac
  if ((10#$actual_major > 10#$required_major)); then
    return 0
  fi
  if ((10#$actual_major == 10#$required_major && 10#$actual_minor >= 10#$required_minor)); then
    return 0
  fi
  return 1
}

require_cuda_compute_capability() {
  require_command "nvidia-smi" "install NVIDIA drivers and ensure nvidia-smi is on PATH"
  local capabilities
  if ! capabilities=$(run_command nvidia-smi --query-gpu=compute_cap --format=csv,noheader,nounits 2>/dev/null); then
    die 2 "cannot query NVIDIA GPU compute capability with nvidia-smi"
  fi
  local capability
  while IFS= read -r capability; do
    capability=${capability//[[:space:]]/}
    if [ -n "$capability" ] && compute_capability_at_least "$capability" "$cuda_min_compute_capability"; then
      return 0
    fi
  done <<<"$capabilities"
  die 2 "no NVIDIA GPU meets CUDA compute capability >= $cuda_min_compute_capability"
}

build_host_jitml() {
  require_command "cabal" "install the pinned Haskell toolchain before building ./.build/jitml"
  local root
  local cabal_binary
  root=$(repo_root)
  cabal_binary=$(command_path cabal)
  mkdir -p "$root/.build"
  info "building host-native jitml binary"
  (cd "$root" && "$cabal_binary" build exe:jitml)
  local built_binary
  built_binary=$(cd "$root" && "$cabal_binary" list-bin exe:jitml)
  if [ ! -x "$built_binary" ]; then
    die 2 "cabal did not produce an executable jitml binary at '$built_binary'"
  fi
  cp "$built_binary" "$root/.build/jitml"
  chmod 0755 "$root/.build/jitml"
  if [ "$(host_uname_s)" = "Darwin" ]; then
    require_command "codesign" "install Xcode Command Line Tools before building ./.build/jitml"
    run_command codesign --force --sign - "$root/.build/jitml" >/dev/null
  fi
  info "wrote ./.build/jitml"
}

run_apple_bootstrap() {
  local root
  root=$(repo_root)
  "$root/.build/jitml" bootstrap --apple-silicon "$@"
}

run_linux_compose_bootstrap() {
  local substrate=$1
  shift || true
  local root
  root=$(repo_root)
  (cd "$root" && run_command docker compose run --rm jitml jitml bootstrap "--$substrate" "$@")
}

run_linux_compose_jitml() {
  local root
  root=$(repo_root)
  (cd "$root" && run_command docker compose run --rm jitml jitml "$@")
}

# CUDA substrate variant: runs the jitml CLI through the GPU-attached
# `jitml-cuda` compose service (NVIDIA Container Runtime) so in-process CUDA
# paths — e.g. the `jitml inference run` live test — see a real device. The
# default `jitml` service has no GPU, which is correct for linux-cpu.
run_linux_cuda_compose_jitml() {
  local root
  root=$(repo_root)
  (cd "$root" && run_command docker compose run --rm jitml-cuda jitml "$@")
}

build_linux_image() {
  require_docker_without_sudo
  local root
  root=$(repo_root)
  (cd "$root" && run_command docker compose build jitml)
}

cluster_name_for_substrate() {
  printf 'jitml-%s\n' "$1"
}

print_cluster_status() {
  local root
  root=$(repo_root)
  local publication="$root/.build/runtime/cluster-publication.json"
  if [ -f "$publication" ]; then
    cat "$publication"
    printf '\n'
  else
    die 3 "cluster publication is missing; run bootstrap/$1.sh up first"
  fi
}

kind_down() {
  local substrate=$1
  local cluster_name
  cluster_name=$(cluster_name_for_substrate "$substrate")
  if have kind; then
    run_command kind delete cluster --name "$cluster_name" || true
  else
    warn "kind is not on PATH; nothing to delete for $cluster_name"
  fi
}

purge_state() {
  local substrate=$1
  local full=${2:-false}
  local root
  root=$(repo_root)
  kind_down "$substrate"
  rm -rf "$root/.data"
  if [ "$full" = "true" ]; then
    rm -rf "$root/.build"
  fi
}

purge_linux_state() {
  local substrate=$1
  local full=${2:-false}
  local root
  root=$(repo_root)
  purge_state "$substrate" "$full"
  if [ "$full" = "true" ]; then
    (cd "$root" && run_command docker compose down --rmi local --volumes || true)
  fi
}

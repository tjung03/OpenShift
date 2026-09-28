#!/usr/bin/env bash

# OpenShift 클러스터의 기본 상태를 변경 없이 조회합니다.
# 일부 리소스는 cluster-admin 또는 별도 RBAC 권한이 필요합니다.
# 개별 조회가 실패해도 다음 항목을 계속 실행하고, 마지막에 실패 수를 반환합니다.

set -uo pipefail

readonly PROGRAM_NAME="${0##*/}"
readonly OC_BIN="${OPENSHIFT_CLI:-oc}"

namespace=""
all_namespaces=false
include_metrics=true
failures=0

usage() {
  cat <<EOF
Usage: ${PROGRAM_NAME} [OPTIONS]

Read-only OpenShift cluster health snapshot.

Options:
  -n, --namespace NAME   Inspect Pods and events in one namespace
  -A, --all-namespaces  Inspect Pods and events across all namespaces
      --skip-metrics    Skip oc adm top checks
  -h, --help            Show this help message

Environment:
  OPENSHIFT_CLI         oc executable path or command name (default: oc)
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 2
}

while (($# > 0)); do
  case "$1" in
    -n|--namespace)
      (($# >= 2)) || die "$1 requires a namespace"
      namespace="$2"
      shift 2
      ;;
    -A|--all-namespaces)
      all_namespaces=true
      shift
      ;;
    --skip-metrics)
      include_metrics=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if [[ -n "$namespace" && "$all_namespaces" == true ]]; then
  die "--namespace and --all-namespaces cannot be used together"
fi

command -v "$OC_BIN" >/dev/null 2>&1 || die "OpenShift CLI not found: $OC_BIN"

# 로그인 검사는 이후 명령에서 반복되는 인증 오류를 줄이기 위해 먼저 수행합니다.
if ! "$OC_BIN" whoami >/dev/null 2>&1; then
  printf 'Error: not logged in or cluster API is unavailable\n' >&2
  exit 3
fi

run_check() {
  local title="$1"
  local status
  shift

  printf '\n## %s\n' "$title"
  printf '$'
  printf ' %q' "$@"
  printf '\n'

  "$@"
  status=$?
  if ((status != 0)); then
    printf 'Warning: check failed with status %d: %s\n' "$status" "$title" >&2
    ((failures += 1))
  fi
}

pod_scope=()
if [[ "$all_namespaces" == true ]]; then
  pod_scope=(-A)
elif [[ -n "$namespace" ]]; then
  pod_scope=(-n "$namespace")
fi

run_check "Current user" "$OC_BIN" whoami
run_check "Current API server" "$OC_BIN" whoami --show-server
run_check "Current context" "$OC_BIN" config current-context
run_check "Client and server versions" "$OC_BIN" version
run_check "ClusterOperators" "$OC_BIN" get clusteroperators
run_check "Nodes" "$OC_BIN" get nodes -o wide
run_check "Pods" "$OC_BIN" get pods "${pod_scope[@]}" -o wide
run_check "Events ordered by last timestamp" "$OC_BIN" get events "${pod_scope[@]}" --sort-by=.lastTimestamp

if [[ "$include_metrics" == true ]]; then
  run_check "Node metrics" "$OC_BIN" adm top node
  run_check "Pod metrics" "$OC_BIN" adm top pod "${pod_scope[@]}" --sum
fi

printf '\n## Summary\n'
if ((failures == 0)); then
  printf 'All requested checks completed. Review resource conditions and event messages above.\n'
  exit 0
fi

printf '%d check(s) failed. Review RBAC, Metrics API, and cluster availability.\n' "$failures" >&2
exit 1

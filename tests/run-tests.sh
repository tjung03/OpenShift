#!/usr/bin/env bash

# 클러스터 연결 없이 상태 점검 스크립트의 제어 흐름을 검증합니다.
# YAML 구문 검사는 Python과 PyYAML이 있을 때 함께 수행합니다.

set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SCRIPT="$ROOT_DIR/scripts/cluster-health-check.sh"
readonly TEMPLATE="$ROOT_DIR/manifests/app-template.yaml"

tests_run=0

pass() {
  ((tests_run += 1))
  printf 'ok %d - %s\n' "$tests_run" "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  [[ "$haystack" == *"$needle"* ]] || fail "$message"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

bash -n "$SCRIPT"
bash -n "$0"
pass "Bash syntax"

help_output="$($SCRIPT --help)"
assert_contains "$help_output" "--all-namespaces" "help should describe namespace scope"
assert_contains "$help_output" "--skip-metrics" "help should describe metrics option"
pass "Help output"

if OPENSHIFT_CLI=command-that-does-not-exist "$SCRIPT" >"$tmp_dir/missing.out" 2>"$tmp_dir/missing.err"; then
  fail "missing oc should fail"
fi
assert_contains "$(<"$tmp_dir/missing.err")" "OpenShift CLI not found" "missing oc error should be clear"
pass "Missing CLI handling"

if "$SCRIPT" --unknown >"$tmp_dir/unknown.out" 2>"$tmp_dir/unknown.err"; then
  fail "unknown option should fail"
fi
assert_contains "$(<"$tmp_dir/unknown.err")" "unknown option" "unknown option error should be clear"
pass "Unknown option handling"

cat >"$tmp_dir/fake-oc" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${FAKE_OC_LOG:?}"
if [[ "$1" == "whoami" && "$#" -eq 1 ]]; then
  printf 'developer\n'
else
  printf 'mock output: %s\n' "$*"
fi
EOF
chmod +x "$tmp_dir/fake-oc"

export FAKE_OC_LOG="$tmp_dir/oc.log"
OPENSHIFT_CLI="$tmp_dir/fake-oc" "$SCRIPT" --namespace demo --skip-metrics >"$tmp_dir/success.out"
success_log="$(<"$FAKE_OC_LOG")"
assert_contains "$success_log" "get pods -n demo -o wide" "namespace should be passed to pod lookup"
assert_contains "$success_log" "get events -n demo --sort-by=.lastTimestamp" "namespace should be passed to event lookup"
if [[ "$success_log" == *"adm top"* ]]; then
  fail "--skip-metrics should omit metric checks"
fi
pass "Read-only namespace checks"

: >"$FAKE_OC_LOG"
OPENSHIFT_CLI="$tmp_dir/fake-oc" "$SCRIPT" --all-namespaces >"$tmp_dir/all.out"
all_log="$(<"$FAKE_OC_LOG")"
assert_contains "$all_log" "get pods -A -o wide" "all-namespaces should be passed to pod lookup"
assert_contains "$all_log" "adm top node" "node metrics should use the canonical command"
assert_contains "$all_log" "adm top pod -A --sum" "pod metrics should preserve the selected scope"
pass "All-namespace and metric checks"

cat >"$tmp_dir/failing-oc" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "whoami" ]]; then
  printf 'developer\n'
  exit 0
fi
if [[ "$*" == "get clusteroperators" ]]; then
  exit 7
fi
printf 'mock output: %s\n' "$*"
EOF
chmod +x "$tmp_dir/failing-oc"

if OPENSHIFT_CLI="$tmp_dir/failing-oc" "$SCRIPT" --skip-metrics >"$tmp_dir/failure.out" 2>"$tmp_dir/failure.err"; then
  fail "a failed check should produce a non-zero summary status"
fi
assert_contains "$(<"$tmp_dir/failure.err")" "1 check(s) failed" "failure summary should contain the count"
pass "Partial failure reporting"

required_patterns=(
  "apiVersion: template.openshift.io/v1"
  "apiVersion: apps/v1"
  'image: ${IMAGE}'
  'replicas: ${{REPLICAS}}'
)
for pattern in "${required_patterns[@]}"; do
  grep -Fq "$pattern" "$TEMPLATE" || fail "template is missing: $pattern"
done
pass "Template resource and parameter fields"

if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  python3 - "$TEMPLATE" <<'PY'
import pathlib
import re
import sys
import yaml

template = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
document = yaml.safe_load(template)
assert document["kind"] == "Template"
assert {item["kind"] for item in document["objects"]} == {"Deployment"}
declared_parameters = {item["name"] for item in document["parameters"]}
assert declared_parameters == {
    "APP_NAME", "IMAGE", "REPLICAS"
}
used_parameters = set(
    re.findall(r"\$\{\{?([A-Z][A-Z0-9_]*)\}\}?", template)
)
assert used_parameters == declared_parameters
PY
  pass "Template YAML and parameter usage"
else
  printf '# SKIP Template YAML parsing: Python 3 with PyYAML is not available\n'
fi

printf '1..%d\n' "$tests_run"

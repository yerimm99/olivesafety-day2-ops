#!/usr/bin/env bash
set -u

AWS_REGION="${AWS_REGION:-ap-northeast-2}"

OPS_CHECK_DIR="${OPS_CHECK_DIR:-/opt/olivesafety/ops-check}"
REPORT_DIR="${REPORT_DIR:-/opt/olivesafety/reports}"
RUN_ID="$(date '+%Y%m%d-%H%M%S')"
SUMMARY_REPORT="${REPORT_DIR}/dev-ops-check-summary-${RUN_ID}.md"
LOG_DIR="${REPORT_DIR}/logs-${RUN_ID}"

PASS_COUNT=0
FAIL_COUNT=0

mkdir -p "${REPORT_DIR}"
mkdir -p "${LOG_DIR}"

write() {
  echo "$@" >> "${SUMMARY_REPORT}"
}

section() {
  write
  write "## $1"
  write
}

run_step() {
  local step_name="$1"
  local command="$2"
  local log_file="$3"

  section "${step_name}"

  write "- Command:"
  write
  write '```bash'
  write "${command}"
  write '```'
  write

  echo
  echo "============================================================"
  echo "${step_name}"
  echo "============================================================"
  echo "Command: ${command}"
  echo

  bash -c "${command}" > "${log_file}" 2>&1
  local status=$?

  if [[ "${status}" -eq 0 ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    write "- Result: PASS"
    echo "[PASS] ${step_name}"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    write "- Result: FAIL"
    echo "[FAIL] ${step_name}"
  fi

  write "- Exit Code: ${status}"
  write "- Log File: ${log_file}"
  write
  write "### Output"
  write
  write '```text'
  tail -120 "${log_file}" >> "${SUMMARY_REPORT}" 2>/dev/null || true
  write '```'
  write

  return 0
}

write "# Dev Ops Check Summary"
write
write "- Generated At: $(date '+%Y-%m-%d %H:%M:%S %Z')"
write "- Hostname: $(hostname)"
write "- AWS Region: ${AWS_REGION}"
write "- Ops Check Directory: ${OPS_CHECK_DIR}"
write "- Report Directory: ${REPORT_DIR}"
write "- Log Directory: ${LOG_DIR}"
write

section "Preflight"

if [[ -d "${OPS_CHECK_DIR}" ]]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  write "- PASS: Ops check directory exists: ${OPS_CHECK_DIR}"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  write "- FAIL: Ops check directory does not exist: ${OPS_CHECK_DIR}"
fi

for script in \
  dev-health-check.sh \
  dev-health-report.sh \
  alb-target-health-check.sh
do
  if [[ -x "${OPS_CHECK_DIR}/${script}" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    write "- PASS: Script is executable: ${script}"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    write "- FAIL: Script is missing or not executable: ${script}"
  fi
done

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  section "Summary"
  write "| Result | Count |"
  write "|---|---:|"
  write "| PASS | ${PASS_COUNT} |"
  write "| FAIL | ${FAIL_COUNT} |"
  write
  write "Overall Status: FAIL"
  echo "[FAIL] Preflight failed. Summary report: ${SUMMARY_REPORT}"
  exit 1
fi

run_step \
  "1. Dev Health Check" \
  "AWS_REGION=${AWS_REGION} ${OPS_CHECK_DIR}/dev-health-check.sh" \
  "${LOG_DIR}/dev-health-check.log"

run_step \
  "2. Dev Health Markdown Report" \
  "AWS_REGION=${AWS_REGION} REPORT_DIR=${REPORT_DIR} ${OPS_CHECK_DIR}/dev-health-report.sh" \
  "${LOG_DIR}/dev-health-report.log"

run_step \
  "3. ALB Target Health Markdown Report" \
  "AWS_REGION=${AWS_REGION} REPORT_DIR=${REPORT_DIR} ${OPS_CHECK_DIR}/alb-target-health-check.sh" \
  "${LOG_DIR}/alb-target-health-check.log"

section "Generated Reports"

write '```text'
find "${REPORT_DIR}" -maxdepth 1 -type f -name "*.md" -printf "%TY-%Tm-%Td %TH:%TM %p\n" 2>/dev/null \
  | sort \
  | tail -20 >> "${SUMMARY_REPORT}" || true
write '```'
write

section "Summary"

write "| Result | Count |"
write "|---|---:|"
write "| PASS | ${PASS_COUNT} |"
write "| FAIL | ${FAIL_COUNT} |"
write

if [[ "${FAIL_COUNT}" -eq 0 ]]; then
  write "Overall Status: PASS"
  echo
  echo "[PASS] Dev ops checks completed successfully."
  echo "Summary report: ${SUMMARY_REPORT}"
  exit 0
else
  write "Overall Status: FAIL"
  echo
  echo "[FAIL] Dev ops checks completed with ${FAIL_COUNT} failure(s)."
  echo "Summary report: ${SUMMARY_REPORT}"
  exit 1
fi

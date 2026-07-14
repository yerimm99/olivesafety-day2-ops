#!/usr/bin/env bash
set -u

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
AWS_PROFILE="${AWS_PROFILE:-}"

NAMESPACE="${NAMESPACE:-olivesafety}"
INGRESS_NAME="${INGRESS_NAME:-olivesafety-api}"
SERVICE_NAME="${SERVICE_NAME:-olivesafety-api}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-olivesafety-api}"

REPORT_DIR="${REPORT_DIR:-/opt/olivesafety/reports}"
REPORT_FILE="${REPORT_DIR}/alb-target-health-report-$(date '+%Y%m%d-%H%M%S').md"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

mkdir -p "${REPORT_DIR}"

aws_cmd() {
  if [[ -n "${AWS_PROFILE}" ]]; then
    aws --region "${AWS_REGION}" --profile "${AWS_PROFILE}" "$@"
  else
    aws --region "${AWS_REGION}" "$@"
  fi
}

write() {
  echo "$@" >> "${REPORT_FILE}"
}

section() {
  write
  write "## $1"
  write
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  write "- PASS: $1"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  write "- WARN: $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  write "- FAIL: $1"
}

code_block_file() {
  local file="$1"

  write '```text'
  cat "${file}" >> "${REPORT_FILE}" 2>/dev/null || true
  write '```'
  write
}

command_output() {
  local title="$1"
  local command="$2"

  write "### ${title}"
  write
  write '```bash'
  write "${command}"
  write '```'
  write
  write '```text'
  bash -c "${command}" >> "${REPORT_FILE}" 2>&1 || true
  write '```'
  write
}

target_reason_hint() {
  local reason="$1"

  case "${reason}" in
    Target.ResponseCodeMismatch)
      echo "Health check path returned unexpected status code. Check /actuator/health, application status code, Spring Security exception rules, and ALB health check path."
      ;;
    Target.Timeout)
      echo "Target did not respond before timeout. Check pod readiness, application port, service targetPort, node/security group/network path."
      ;;
    Target.FailedHealthChecks)
      echo "Target failed repeated health checks. Check readiness endpoint, application logs, pod events, and service endpoint mapping."
      ;;
    Elb.InternalError)
      echo "ALB internal error. Retry after a while and check AWS Load Balancer events."
      ;;
    Target.NotRegistered)
      echo "Target is not registered. Check Kubernetes Service endpoints and AWS Load Balancer Controller reconciliation."
      ;;
    *)
      echo "Check TargetHealth reason, pod status, service endpoints, ingress annotations, and application health endpoint."
      ;;
  esac
}

write "# ALB Target Health Report"
write
write "- Generated At: $(date '+%Y-%m-%d %H:%M:%S %Z')"
write "- Hostname: $(hostname)"
write "- AWS Region: ${AWS_REGION}"
write "- Namespace: ${NAMESPACE}"
write "- Ingress: ${INGRESS_NAME}"
write "- Service: ${SERVICE_NAME}"
write "- Deployment: ${DEPLOYMENT_NAME}"
write

section "1. Kubernetes Ingress"

APP_ALB_DNS="$(kubectl get ingress "${INGRESS_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/tmp/alb-ingress.err || true)"

if [[ -n "${APP_ALB_DNS}" ]]; then
  pass "Ingress has ALB DNS."
  write "- ALB DNS: ${APP_ALB_DNS}"
else
  fail "Ingress does not have ALB DNS."
  code_block_file /tmp/alb-ingress.err
fi

command_output "Ingress Status" \
  "kubectl get ingress ${INGRESS_NAME} -n ${NAMESPACE} -o wide"

section "2. AWS Load Balancer"

ALB_ARN=""

if [[ -n "${APP_ALB_DNS}" ]]; then
  ALB_ARN="$(aws_cmd elbv2 describe-load-balancers \
    --query "LoadBalancers[?DNSName=='${APP_ALB_DNS}'].LoadBalancerArn | [0]" \
    --output text 2>/tmp/alb-describe.err || true)"

  if [[ -n "${ALB_ARN}" && "${ALB_ARN}" != "None" ]]; then
    pass "ALB ARN was found from DNS name."
    write "- ALB ARN: ${ALB_ARN}"
  else
    fail "Failed to find ALB ARN from DNS name."
    code_block_file /tmp/alb-describe.err
  fi
fi

if [[ -n "${ALB_ARN}" && "${ALB_ARN}" != "None" ]]; then
  write
  write "### Load Balancer Detail"
  write
  aws_cmd elbv2 describe-load-balancers \
    --load-balancer-arns "${ALB_ARN}" \
    --output json > /tmp/alb-detail.json 2>/tmp/alb-detail.err || true

  if [[ -s /tmp/alb-detail.json ]]; then
    write '```json'
    jq '.LoadBalancers[] | {LoadBalancerName, DNSName, Scheme, VpcId, State, Type}' /tmp/alb-detail.json >> "${REPORT_FILE}" 2>/dev/null || cat /tmp/alb-detail.json >> "${REPORT_FILE}"
    write '```'
  else
    code_block_file /tmp/alb-detail.err
  fi
fi

section "3. Target Groups"

TARGET_GROUP_ARNS=()

if [[ -n "${ALB_ARN}" && "${ALB_ARN}" != "None" ]]; then
  aws_cmd elbv2 describe-target-groups \
    --load-balancer-arn "${ALB_ARN}" \
    --output json > /tmp/alb-target-groups.json 2>/tmp/alb-target-groups.err || true

  if [[ -s /tmp/alb-target-groups.json ]]; then
    TG_COUNT="$(jq '.TargetGroups | length' /tmp/alb-target-groups.json 2>/dev/null || echo 0)"

    if [[ "${TG_COUNT}" -gt 0 ]]; then
      pass "Target Group exists. Count=${TG_COUNT}"

      write
      write "### Target Group List"
      write
      write '```json'
      jq '.TargetGroups[] | {TargetGroupName, TargetGroupArn, Protocol, Port, TargetType, HealthCheckPath, HealthCheckProtocol, HealthCheckPort, Matcher}' /tmp/alb-target-groups.json >> "${REPORT_FILE}" 2>/dev/null || cat /tmp/alb-target-groups.json >> "${REPORT_FILE}"
      write '```'
      write

      while IFS= read -r tg_arn; do
        TARGET_GROUP_ARNS+=("${tg_arn}")
      done < <(jq -r '.TargetGroups[].TargetGroupArn' /tmp/alb-target-groups.json)
    else
      fail "No Target Group is attached to ALB."
    fi
  else
    fail "Failed to describe target groups."
    code_block_file /tmp/alb-target-groups.err
  fi
fi

section "4. Target Health"

if [[ "${#TARGET_GROUP_ARNS[@]}" -eq 0 ]]; then
  fail "No target group ARN available for target health check."
else
  for tg_arn in "${TARGET_GROUP_ARNS[@]}"; do
    TG_NAME="$(echo "${tg_arn}" | awk -F: '{print $NF}' | cut -d/ -f2)"

    write "### Target Group: ${TG_NAME}"
    write
    write "- TargetGroupArn: ${tg_arn}"
    write

    aws_cmd elbv2 describe-target-health \
      --target-group-arn "${tg_arn}" \
      --output json > /tmp/alb-target-health.json 2>/tmp/alb-target-health.err || true

    if [[ ! -s /tmp/alb-target-health.json ]]; then
      fail "Failed to describe target health for ${TG_NAME}."
      code_block_file /tmp/alb-target-health.err
      continue
    fi

    TARGET_COUNT="$(jq '.TargetHealthDescriptions | length' /tmp/alb-target-health.json 2>/dev/null || echo 0)"

    if [[ "${TARGET_COUNT}" -eq 0 ]]; then
      fail "No registered target exists in ${TG_NAME}."
      continue
    fi

    HEALTHY_COUNT="$(jq '[.TargetHealthDescriptions[] | select(.TargetHealth.State == "healthy")] | length' /tmp/alb-target-health.json)"
    UNHEALTHY_COUNT="$(jq '[.TargetHealthDescriptions[] | select(.TargetHealth.State == "unhealthy")] | length' /tmp/alb-target-health.json)"
    INITIAL_COUNT="$(jq '[.TargetHealthDescriptions[] | select(.TargetHealth.State == "initial")] | length' /tmp/alb-target-health.json)"
    OTHER_COUNT="$(jq '[.TargetHealthDescriptions[] | select(.TargetHealth.State != "healthy" and .TargetHealth.State != "unhealthy" and .TargetHealth.State != "initial")] | length' /tmp/alb-target-health.json)"

    write "- Total Targets: ${TARGET_COUNT}"
    write "- Healthy: ${HEALTHY_COUNT}"
    write "- Unhealthy: ${UNHEALTHY_COUNT}"
    write "- Initial: ${INITIAL_COUNT}"
    write "- Other: ${OTHER_COUNT}"
    write

    write '```json'
    jq '.TargetHealthDescriptions[] | {
      Target: .Target,
      State: .TargetHealth.State,
      Reason: .TargetHealth.Reason,
      Description: .TargetHealth.Description
    }' /tmp/alb-target-health.json >> "${REPORT_FILE}"
    write '```'
    write

    if [[ "${UNHEALTHY_COUNT}" -gt 0 ]]; then
      fail "Unhealthy target exists in ${TG_NAME}."

      write "#### Suggested Checks"
      write

      jq -r '.TargetHealthDescriptions[] | select(.TargetHealth.State == "unhealthy") | .TargetHealth.Reason // "Unknown"' /tmp/alb-target-health.json | sort -u | while read -r reason; do
        hint="$(target_reason_hint "${reason}")"
        write "- Reason: ${reason}"
        write "  - Hint: ${hint}"
      done

      write
    elif [[ "${INITIAL_COUNT}" -gt 0 || "${OTHER_COUNT}" -gt 0 ]]; then
      warn "Some targets are not healthy yet in ${TG_NAME}."
    else
      pass "All targets are healthy in ${TG_NAME}."
    fi
  done
fi

section "5. Kubernetes Service / Endpoint / Pod Cross Check"

command_output "Service Status" \
  "kubectl get service ${SERVICE_NAME} -n ${NAMESPACE} -o wide"

command_output "EndpointSlice Status" \
  "kubectl get endpointslice -n ${NAMESPACE} -l kubernetes.io/service-name=${SERVICE_NAME} -o wide"

command_output "Deployment and Pods" \
  "kubectl get deploy,rs,pods -n ${NAMESPACE} -o wide"

command_output "Recent Events" \
  "kubectl get events -n ${NAMESPACE} --sort-by=.lastTimestamp | tail -30"

section "6. Summary"

write "| Result | Count |"
write "|---|---:|"
write "| PASS | ${PASS_COUNT} |"
write "| WARN | ${WARN_COUNT} |"
write "| FAIL | ${FAIL_COUNT} |"
write

if [[ "${FAIL_COUNT}" -eq 0 ]]; then
  write "Overall Status: PASS"
  echo "[PASS] ALB target health report generated: ${REPORT_FILE}"
  exit 0
else
  write "Overall Status: FAIL"
  echo "[FAIL] ALB target health report generated with ${FAIL_COUNT} failure(s): ${REPORT_FILE}"
  exit 1
fi

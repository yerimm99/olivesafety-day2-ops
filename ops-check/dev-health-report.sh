#!/usr/bin/env bash
set -u

AWS_REGION="${AWS_REGION:-ap-northeast-2}"

NAMESPACE="olivesafety"
ARGOCD_NAMESPACE="argocd"
ARGOCD_APP="olivesafety-dev"
DEPLOYMENT_NAME="olivesafety-api"
INGRESS_NAME="olivesafety-api"
EXTERNAL_SECRET_NAME="olivesafety-api-secret"
ECR_REPOSITORY_NAME="olivesafety-day2-ops-dev/olivesafety-api"

REPORT_DIR="${REPORT_DIR:-/opt/olivesafety/reports}"
REPORT_FILE="${REPORT_DIR}/dev-health-report-$(date '+%Y%m%d-%H%M%S').md"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

mkdir -p "${REPORT_DIR}"

write() {
  echo "$@" >> "${REPORT_FILE}"
}

section() {
  write
  write "## $1"
  write
}

code_block() {
  write '```text'
  cat >> "${REPORT_FILE}"
  write '```'
  write
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  write "- PASS: $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  write "- FAIL: $1"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  write "- WARN: $1"
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

write "# Dev Environment Health Report"
write
write "- Generated At: $(date '+%Y-%m-%d %H:%M:%S %Z')"
write "- Hostname: $(hostname)"
write "- Namespace: ${NAMESPACE}"
write "- ArgoCD Application: ${ARGOCD_APP}"
write "- AWS Region: ${AWS_REGION}"
write

section "1. AWS Identity"

AWS_IDENTITY="$(aws sts get-caller-identity 2>/tmp/report-aws-identity.err || true)"

if [[ -n "${AWS_IDENTITY}" ]]; then
  pass "AWS identity is available."
  write
  write '```json'
  echo "${AWS_IDENTITY}" >> "${REPORT_FILE}"
  write '```'
else
  fail "AWS identity is not available."
  write
  write '```text'
  cat /tmp/report-aws-identity.err >> "${REPORT_FILE}" 2>/dev/null || true
  write '```'
fi

section "2. Kubernetes Cluster"

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

if [[ -n "${CURRENT_CONTEXT}" ]]; then
  pass "kubectl context is configured: ${CURRENT_CONTEXT}"
else
  fail "kubectl context is not configured."
fi

if kubectl get nodes >/tmp/report-nodes.txt 2>&1; then
  pass "EKS nodes are reachable."
else
  fail "Failed to get EKS nodes."
fi

write
write "### Nodes"
write
cat /tmp/report-nodes.txt | code_block

section "3. ArgoCD Application"

SYNC_STATUS="$(kubectl get application "${ARGOCD_APP}" -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
HEALTH_STATUS="$(kubectl get application "${ARGOCD_APP}" -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"

write "- Sync Status: ${SYNC_STATUS:-Unknown}"
write "- Health Status: ${HEALTH_STATUS:-Unknown}"
write

if [[ "${SYNC_STATUS}" == "Synced" && "${HEALTH_STATUS}" == "Healthy" ]]; then
  pass "ArgoCD application is Synced / Healthy."
else
  fail "ArgoCD application is not Synced / Healthy."
fi

command_output "ArgoCD Application Conditions" \
  "kubectl get application ${ARGOCD_APP} -n ${ARGOCD_NAMESPACE} -o jsonpath='{range .status.conditions[*]}{.type}{\" | \"}{.message}{\"\\n\"}{end}'"

command_output "ArgoCD Managed Resources" \
  "kubectl get application ${ARGOCD_APP} -n ${ARGOCD_NAMESPACE} -o jsonpath='{range .status.resources[*]}{.kind}{\" / \"}{.name}{\" / \"}{.status}{\" / \"}{.health.status}{\"\\n\"}{end}'"

section "4. Kubernetes Workloads"

if kubectl rollout status deployment/"${DEPLOYMENT_NAME}" -n "${NAMESPACE}" --timeout=60s >/tmp/report-rollout.txt 2>&1; then
  pass "Deployment rollout is complete."
else
  fail "Deployment rollout is not complete."
fi

write
write "### Deployment Rollout"
write
cat /tmp/report-rollout.txt | code_block

command_output "Deployments / ReplicaSets / Pods / HPA" \
  "kubectl get deploy,rs,pods,hpa -n ${NAMESPACE}"

NOT_RUNNING_PODS="$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | awk '$3 != "Running" && $3 != "Completed" {print $1 " " $3}' || true)"

if [[ -z "${NOT_RUNNING_PODS}" ]]; then
  pass "All pods are Running or Completed."
else
  fail "Some pods are not Running."
  write
  write '```text'
  echo "${NOT_RUNNING_PODS}" >> "${REPORT_FILE}"
  write '```'
fi

section "5. External Secrets"

ES_READY="$(kubectl get externalsecret "${EXTERNAL_SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"

if [[ "${ES_READY}" == "True" ]]; then
  pass "ExternalSecret is Ready."
else
  fail "ExternalSecret is not Ready."
fi

if kubectl get secret "${EXTERNAL_SECRET_NAME}" -n "${NAMESPACE}" >/tmp/report-secret.txt 2>&1; then
  pass "Kubernetes Secret exists: ${EXTERNAL_SECRET_NAME}"
else
  fail "Kubernetes Secret does not exist: ${EXTERNAL_SECRET_NAME}"
fi

command_output "ExternalSecret Status" \
  "kubectl get externalsecret ${EXTERNAL_SECRET_NAME} -n ${NAMESPACE} -o wide"

section "6. Ingress and ALB Health"

APP_ALB_DNS="$(kubectl get ingress "${INGRESS_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"

if [[ -n "${APP_ALB_DNS}" ]]; then
  pass "ALB DNS is assigned."
  write "- ALB DNS: ${APP_ALB_DNS}"
else
  fail "ALB DNS is not assigned."
fi

if [[ -n "${APP_ALB_DNS}" ]]; then
  HEALTH_RESPONSE="$(curl -s --max-time 10 "http://${APP_ALB_DNS}/actuator/health" || true)"
  write
  write "### Application Health Response"
  write
  write '```json'
  echo "${HEALTH_RESPONSE}" >> "${REPORT_FILE}"
  write '```'

  if echo "${HEALTH_RESPONSE}" | grep -q '"status":"UP"'; then
    pass "Application health check is UP."
  else
    fail "Application health check is not UP."
  fi
fi

command_output "Ingress Status" \
  "kubectl get ingress ${INGRESS_NAME} -n ${NAMESPACE} -o wide"

section "7. ECR Image"

DEPLOYED_IMAGE="$(kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
IMAGE_TAG="${DEPLOYED_IMAGE##*:}"

write "- Deployed Image: ${DEPLOYED_IMAGE:-Unknown}"
write "- Image Tag: ${IMAGE_TAG:-Unknown}"
write

if [[ -n "${DEPLOYED_IMAGE}" && "${IMAGE_TAG}" != "${DEPLOYED_IMAGE}" ]]; then
  pass "Deployed image tag was parsed successfully."

  if aws ecr describe-images \
    --repository-name "${ECR_REPOSITORY_NAME}" \
    --image-ids imageTag="${IMAGE_TAG}" \
    --region "${AWS_REGION}" >/tmp/report-ecr.txt 2>&1; then

    pass "ECR image exists: ${ECR_REPOSITORY_NAME}:${IMAGE_TAG}"
  else
    fail "ECR image does not exist or cannot be described."
    write
    write '```text'
    cat /tmp/report-ecr.txt >> "${REPORT_FILE}"
    write '```'
  fi
else
  fail "Failed to parse deployed image tag."
fi

section "8. Summary"

write "| Result | Count |"
write "|---|---:|"
write "| PASS | ${PASS_COUNT} |"
write "| WARN | ${WARN_COUNT} |"
write "| FAIL | ${FAIL_COUNT} |"
write

if [[ "${FAIL_COUNT}" -eq 0 ]]; then
  write "Overall Status: PASS"
  echo "[PASS] Report generated: ${REPORT_FILE}"
  exit 0
else
  write "Overall Status: FAIL"
  echo "[FAIL] Report generated with ${FAIL_COUNT} failure(s): ${REPORT_FILE}"
  exit 1
fi

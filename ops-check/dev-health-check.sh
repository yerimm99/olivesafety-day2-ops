#!/usr/bin/env bash
set -u

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
AWS_PROFILE="${AWS_PROFILE:-}"

NAMESPACE="olivesafety"
ARGOCD_NAMESPACE="argocd"
ARGOCD_APP="olivesafety-dev"
DEPLOYMENT_NAME="olivesafety-api"
INGRESS_NAME="olivesafety-api"
EXTERNAL_SECRET_NAME="olivesafety-api-secret"
ECR_REPOSITORY_NAME="olivesafety-day2-ops-dev/olivesafety-api"

FAIL_COUNT=0

section() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

pass() {
  echo "[PASS] $1"
}

fail() {
  echo "[FAIL] $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

info() {
  echo "[INFO] $1"
}

aws_base_args() {
  if [[ -n "${AWS_PROFILE}" ]]; then
    echo "--region ${AWS_REGION} --profile ${AWS_PROFILE}"
  else
    echo "--region ${AWS_REGION}"
  fi
}

section "1. Kubernetes Context"

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

if [[ -n "${CURRENT_CONTEXT}" ]]; then
  pass "kubectl context: ${CURRENT_CONTEXT}"
else
  fail "kubectl context not found"
fi

if kubectl get nodes >/tmp/ops-check-nodes.txt 2>&1; then
  pass "Kubernetes nodes are reachable"
  cat /tmp/ops-check-nodes.txt
else
  fail "Failed to get Kubernetes nodes"
  cat /tmp/ops-check-nodes.txt
fi

section "2. ArgoCD Application"

SYNC_STATUS="$(kubectl get application "${ARGOCD_APP}" -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
HEALTH_STATUS="$(kubectl get application "${ARGOCD_APP}" -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"

info "ArgoCD status: ${SYNC_STATUS:-Unknown} / ${HEALTH_STATUS:-Unknown}"

if [[ "${SYNC_STATUS}" == "Synced" && "${HEALTH_STATUS}" == "Healthy" ]]; then
  pass "ArgoCD application is Synced / Healthy"
else
  fail "ArgoCD application is not Synced / Healthy"

  echo
  echo "Application conditions:"
  kubectl get application "${ARGOCD_APP}" -n "${ARGOCD_NAMESPACE}" \
    -o jsonpath='{range .status.conditions[*]}{.type}{" | "}{.message}{"\n"}{end}' 2>/dev/null || true

  echo
  echo "Application resources:"
  kubectl get application "${ARGOCD_APP}" -n "${ARGOCD_NAMESPACE}" \
    -o jsonpath='{range .status.resources[*]}{.kind}{" / "}{.name}{" / "}{.status}{" / "}{.health.status}{"\n"}{end}' 2>/dev/null || true
fi

section "3. Deployment and Pods"

if kubectl rollout status deployment/"${DEPLOYMENT_NAME}" -n "${NAMESPACE}" --timeout=60s >/tmp/ops-check-rollout.txt 2>&1; then
  pass "Deployment rollout completed"
else
  fail "Deployment rollout is not complete"
fi

cat /tmp/ops-check-rollout.txt
echo

kubectl get deploy,rs,pods,hpa -n "${NAMESPACE}" || true

NOT_RUNNING_PODS="$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | awk '$3 != "Running" && $3 != "Completed" {print $1 " " $3}' || true)"

if [[ -z "${NOT_RUNNING_PODS}" ]]; then
  pass "All pods are Running or Completed"
else
  fail "Some pods are not Running"
  echo "${NOT_RUNNING_PODS}"
fi

section "4. External Secrets"

ES_READY="$(kubectl get externalsecret "${EXTERNAL_SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"

if [[ "${ES_READY}" == "True" ]]; then
  pass "ExternalSecret is Ready"
else
  fail "ExternalSecret is not Ready"
  kubectl describe externalsecret "${EXTERNAL_SECRET_NAME}" -n "${NAMESPACE}" 2>/dev/null || true
fi

if kubectl get secret "${EXTERNAL_SECRET_NAME}" -n "${NAMESPACE}" >/tmp/ops-check-secret.txt 2>&1; then
  pass "Kubernetes Secret exists: ${EXTERNAL_SECRET_NAME}"
else
  fail "Kubernetes Secret does not exist: ${EXTERNAL_SECRET_NAME}"
  cat /tmp/ops-check-secret.txt
fi

section "5. Ingress and ALB Health"

APP_ALB_DNS="$(kubectl get ingress "${INGRESS_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"

if [[ -n "${APP_ALB_DNS}" ]]; then
  pass "ALB DNS is assigned"
  info "ALB DNS: ${APP_ALB_DNS}"
else
  fail "ALB DNS is not assigned"
fi

if [[ -n "${APP_ALB_DNS}" ]]; then
  HEALTH_RESPONSE="$(curl -s --max-time 10 "http://${APP_ALB_DNS}/actuator/health" || true)"
  info "Health response: ${HEALTH_RESPONSE}"

  if echo "${HEALTH_RESPONSE}" | grep -q '"status":"UP"'; then
    pass "Application health check is UP"
  else
    fail "Application health check is not UP"
  fi
fi

section "6. ECR Image Tag"

DEPLOYED_IMAGE="$(kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
IMAGE_TAG="${DEPLOYED_IMAGE##*:}"

if [[ -n "${DEPLOYED_IMAGE}" && "${IMAGE_TAG}" != "${DEPLOYED_IMAGE}" ]]; then
  pass "Deployed image detected: ${DEPLOYED_IMAGE}"
  info "Image tag: ${IMAGE_TAG}"
else
  fail "Failed to parse deployed image tag"
fi

AWS_ARGS="$(aws_base_args)"

if [[ -n "${IMAGE_TAG}" && "${IMAGE_TAG}" != "${DEPLOYED_IMAGE}" ]]; then
  if aws ecr describe-images \
    --repository-name "${ECR_REPOSITORY_NAME}" \
    --image-ids imageTag="${IMAGE_TAG}" \
    ${AWS_ARGS} >/tmp/ops-check-ecr.txt 2>&1; then

    pass "ECR image exists: ${ECR_REPOSITORY_NAME}:${IMAGE_TAG}"
  else
    fail "ECR image does not exist or cannot be described: ${ECR_REPOSITORY_NAME}:${IMAGE_TAG}"
    cat /tmp/ops-check-ecr.txt
  fi
fi

section "7. Summary"

if [[ "${FAIL_COUNT}" -eq 0 ]]; then
  echo "[PASS] Dev environment health check completed successfully."
  exit 0
else
  echo "[FAIL] Dev environment health check completed with ${FAIL_COUNT} failure(s)."
  exit 1
fi

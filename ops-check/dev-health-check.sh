#!/usr/bin/env bash
set -u

AWS_PROFILE="${AWS_PROFILE:-yerim-admin}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
PROJECT_NAME="olivesafety-day2-ops"
ENV="dev"
NAMESPACE="olivesafety"
ARGOCD_NAMESPACE="argocd"
APP_NAME="olivesafety-dev"
DEPLOYMENT_NAME="olivesafety-api"
INGRESS_NAME="olivesafety-api"
EXTERNAL_SECRET_NAME="olivesafety-api-secret"
ECR_REPOSITORY_NAME="${PROJECT_NAME}-${ENV}/olivesafety-api"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUSTOMIZATION_PATH="${ROOT_DIR}/k8s/overlays/dev/kustomization.yaml"

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

get_image_tag() {
  python3 - <<PY
from pathlib import Path

path = Path("${KUSTOMIZATION_PATH}")
lines = path.read_text().splitlines()

in_images = False
target = False

for line in lines:
    stripped = line.strip()

    if stripped == "images:":
        in_images = True
        continue

    if in_images and stripped.startswith("- name:"):
        target = stripped == "- name: olivesafety-api"
        continue

    if in_images and target and stripped.startswith("newTag:"):
        print(stripped.split(":", 1)[1].strip())
        break
PY
}

section "1. Kubernetes Context"

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

if [[ -n "${CURRENT_CONTEXT}" ]]; then
  pass "kubectl context: ${CURRENT_CONTEXT}"
else
  fail "kubectl context not found"
fi

kubectl get nodes >/tmp/ops-check-nodes.txt 2>&1
if [[ $? -eq 0 ]]; then
  pass "Kubernetes nodes are reachable"
  cat /tmp/ops-check-nodes.txt
else
  fail "Failed to get Kubernetes nodes"
  cat /tmp/ops-check-nodes.txt
fi

section "2. ArgoCD Application"

SYNC_STATUS="$(kubectl get application "${APP_NAME}" -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
HEALTH_STATUS="$(kubectl get application "${APP_NAME}" -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"

info "ArgoCD status: ${SYNC_STATUS:-Unknown} / ${HEALTH_STATUS:-Unknown}"

if [[ "${SYNC_STATUS}" == "Synced" && "${HEALTH_STATUS}" == "Healthy" ]]; then
  pass "ArgoCD application is Synced / Healthy"
else
  fail "ArgoCD application is not Synced / Healthy"

  echo
  echo "Application conditions:"
  kubectl get application "${APP_NAME}" -n "${ARGOCD_NAMESPACE}" \
    -o jsonpath='{range .status.conditions[*]}{.type}{" | "}{.message}{"\n"}{end}' 2>/dev/null || true

  echo
  echo "Application resources:"
  kubectl get application "${APP_NAME}" -n "${ARGOCD_NAMESPACE}" \
    -o jsonpath='{range .status.resources[*]}{.kind}{" / "}{.name}{" / "}{.status}{" / "}{.health.status}{"\n"}{end}' 2>/dev/null || true
fi

section "3. Deployment and Pods"

kubectl rollout status deployment/"${DEPLOYMENT_NAME}" -n "${NAMESPACE}" --timeout=60s >/tmp/ops-check-rollout.txt 2>&1
if [[ $? -eq 0 ]]; then
  pass "Deployment rollout completed"
else
  fail "Deployment rollout is not complete"
fi
cat /tmp/ops-check-rollout.txt

echo
kubectl get deploy,rs,pods,hpa -n "${NAMESPACE}"

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

kubectl get secret "${EXTERNAL_SECRET_NAME}" -n "${NAMESPACE}" >/tmp/ops-check-secret.txt 2>&1
if [[ $? -eq 0 ]]; then
  pass "Kubernetes Secret exists: ${EXTERNAL_SECRET_NAME}"
else
  fail "Kubernetes Secret does not exist: ${EXTERNAL_SECRET_NAME}"
  cat /tmp/ops-check-secret.txt
fi

section "5. Ingress and ALB Health Check"

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

IMAGE_TAG="$(get_image_tag)"

if [[ -n "${IMAGE_TAG}" ]]; then
  pass "Image tag found in kustomization.yaml: ${IMAGE_TAG}"
else
  fail "Image tag not found in kustomization.yaml"
fi

if [[ -n "${IMAGE_TAG}" ]]; then
  aws ecr describe-images \
    --repository-name "${ECR_REPOSITORY_NAME}" \
    --image-ids imageTag="${IMAGE_TAG}" \
    --region "${AWS_REGION}" \
    --profile "${AWS_PROFILE}" >/tmp/ops-check-ecr.txt 2>&1

  if [[ $? -eq 0 ]]; then
    pass "ECR image exists: ${ECR_REPOSITORY_NAME}:${IMAGE_TAG}"
  else
    fail "ECR image does not exist: ${ECR_REPOSITORY_NAME}:${IMAGE_TAG}"
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

#!/usr/bin/env bash
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-yerim-admin}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
export AWS_PROFILE AWS_REGION

PROJECT_NAME="olivesafety-day2-ops"
ENV="dev"
CLUSTER_NAME="${PROJECT_NAME}-${ENV}-eks"

ALB_ROLE_NAME="${PROJECT_NAME}-${ENV}-aws-load-balancer-controller-role"
EXTERNAL_SECRETS_ROLE_NAME="${PROJECT_NAME}-${ENV}-external-secrets-role"
ECR_REPOSITORY_NAME="${PROJECT_NAME}-${ENV}/olivesafety-api"

BUILD_BOOTSTRAP_IMAGE="${BUILD_BOOTSTRAP_IMAGE:-true}"
INSTALL_MONITORING="${INSTALL_MONITORING:-true}"
RUN_FINAL_TERRAFORM_APPLY="${RUN_FINAL_TERRAFORM_APPLY:-true}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/envs/dev"
KUSTOMIZATION_PATH="${ROOT_DIR}/k8s/overlays/dev/kustomization.yaml"
ARGOCD_APP_PATH="${ROOT_DIR}/argocd/apps/olivesafety-dev.yaml"
PROM_VALUES_PATH="${ROOT_DIR}/observability/kube-prometheus-stack-values.yaml"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: $1 command not found"
    exit 1
  }
}

get_kustomize_image_tag() {
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

get_kustomize_image_name() {
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

    if in_images and target and stripped.startswith("newName:"):
        print(stripped.split(":", 1)[1].strip())
        break
PY
}

echo "==> [0/11] Preflight checks"
require_command aws
require_command terraform
require_command kubectl
require_command helm
require_command python3
require_command docker
require_command curl

if [[ ! -f "${TF_DIR}/terraform.tfvars" ]]; then
  echo "ERROR: ${TF_DIR}/terraform.tfvars not found"
  exit 1
fi

if [[ ! -f "${KUSTOMIZATION_PATH}" ]]; then
  echo "ERROR: ${KUSTOMIZATION_PATH} not found"
  exit 1
fi

if [[ ! -f "${ARGOCD_APP_PATH}" ]]; then
  echo "ERROR: ${ARGOCD_APP_PATH} not found"
  exit 1
fi

echo "AWS_PROFILE=${AWS_PROFILE}"
echo "AWS_REGION=${AWS_REGION}"
echo "CLUSTER_NAME=${CLUSTER_NAME}"

echo "==> [1/11] Terraform apply"
cd "${TF_DIR}"
terraform init
terraform apply -auto-approve

echo "==> [2/11] Update kubeconfig"
aws eks update-kubeconfig \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}"

echo "==> [3/11] Get Terraform outputs"
ECR_URL="$(terraform output -raw ecr_repository_url)"
API_ROLE_ARN="$(terraform output -raw api_irsa_role_arn)"
SQS_QUEUE_URL="$(terraform output -raw sqs_queue_url)"
SNS_TOPIC_ARN="$(terraform output -raw sns_topic_arn)"

IMAGE_TAG="${IMAGE_TAG:-$(get_kustomize_image_tag)}"
MANIFEST_IMAGE_NAME="$(get_kustomize_image_name)"

echo "ECR_URL=${ECR_URL}"
echo "MANIFEST_IMAGE_NAME=${MANIFEST_IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "API_ROLE_ARN=${API_ROLE_ARN}"
echo "SQS_QUEUE_URL=${SQS_QUEUE_URL}"
echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}"

if [[ -z "${IMAGE_TAG}" ]]; then
  echo "ERROR: Failed to read image newTag from ${KUSTOMIZATION_PATH}"
  exit 1
fi

if [[ "${MANIFEST_IMAGE_NAME}" != "${ECR_URL}" ]]; then
  echo "WARNING: kustomization newName does not match Terraform ECR URL."
  echo "  manifest: ${MANIFEST_IMAGE_NAME}"
  echo "  terraform: ${ECR_URL}"
  echo "ArgoCD will deploy the image defined in Git."
fi

cd "${ROOT_DIR}"

echo "==> [4/11] Install AWS Load Balancer Controller"
ALB_ROLE_ARN="$(aws iam get-role \
  --role-name "${ALB_ROLE_NAME}" \
  --profile "${AWS_PROFILE}" \
  --query 'Role.Arn' \
  --output text)"

VPC_ID="$(aws eks describe-cluster \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)"

helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set region="${AWS_REGION}" \
  --set vpcId="${VPC_ID}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${ALB_ROLE_ARN}" \
  --wait \
  --timeout 5m

kubectl rollout status deployment/aws-load-balancer-controller \
  -n kube-system \
  --timeout=300s

echo "Waiting for AWS Load Balancer webhook endpoints..."
WEBHOOK_READY=false

for i in {1..30}; do
  ENDPOINTS="$(kubectl get endpoints aws-load-balancer-webhook-service \
    -n kube-system \
    -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"

  if [[ -n "${ENDPOINTS}" ]]; then
    echo "AWS Load Balancer webhook endpoints ready: ${ENDPOINTS}"
    WEBHOOK_READY=true
    break
  fi

  echo "Waiting for webhook endpoints... ${i}/30"
  sleep 5
done

if [[ "${WEBHOOK_READY}" != "true" ]]; then
  echo "ERROR: AWS Load Balancer webhook endpoints are not ready."
  kubectl get pods -n kube-system | grep aws-load-balancer-controller || true
  kubectl describe deployment aws-load-balancer-controller -n kube-system || true
  exit 1
fi

echo "==> [5/11] Install External Secrets Operator"
EXTERNAL_SECRETS_ROLE_ARN="$(aws iam get-role \
  --role-name "${EXTERNAL_SECRETS_ROLE_NAME}" \
  --profile "${AWS_PROFILE}" \
  --query 'Role.Arn' \
  --output text)"

helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --set serviceAccount.create=true \
  --set serviceAccount.name=external-secrets \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${EXTERNAL_SECRETS_ROLE_ARN}" \
  --wait \
  --timeout 5m

kubectl rollout status deployment/external-secrets \
  -n external-secrets \
  --timeout=300s

kubectl wait --for=condition=Established \
  crd/externalsecrets.external-secrets.io \
  --timeout=120s

kubectl wait --for=condition=Established \
  crd/clustersecretstores.external-secrets.io \
  --timeout=120s

echo "External Secrets ServiceAccount annotation:"
kubectl get sa external-secrets -n external-secrets \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}' || true

echo "==> [6/11] Install monitoring CRDs and kube-prometheus-stack"
if [[ "${INSTALL_MONITORING}" == "true" ]]; then
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update >/dev/null

  if [[ -f "${PROM_VALUES_PATH}" ]]; then
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
      -n monitoring \
      --create-namespace \
      -f "${PROM_VALUES_PATH}" \
      --wait \
      --timeout 10m
  else
    echo "WARNING: ${PROM_VALUES_PATH} not found. Installing kube-prometheus-stack with default values."
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
      -n monitoring \
      --create-namespace \
      --wait \
      --timeout 10m
  fi

  kubectl wait --for=condition=Established \
    crd/servicemonitors.monitoring.coreos.com \
    --timeout=180s

  kubectl wait --for=condition=Established \
    crd/prometheusrules.monitoring.coreos.com \
    --timeout=180s
else
  echo "Skipping monitoring install. INSTALL_MONITORING=false"
fi

echo "==> [7/11] Build and push bootstrap image if missing"
if [[ "${BUILD_BOOTSTRAP_IMAGE}" == "true" ]]; then
  if aws ecr describe-images \
    --repository-name "${ECR_REPOSITORY_NAME}" \
    --image-ids imageTag="${IMAGE_TAG}" \
    --region "${AWS_REGION}" \
    --profile "${AWS_PROFILE}" >/dev/null 2>&1; then

    echo "Image already exists in ECR: ${ECR_URL}:${IMAGE_TAG}"
  else
    echo "Image does not exist in ECR. Building bootstrap image: ${ECR_URL}:${IMAGE_TAG}"

    aws ecr get-login-password \
      --region "${AWS_REGION}" \
      --profile "${AWS_PROFILE}" \
      | docker login --username AWS --password-stdin "$(echo "${ECR_URL}" | cut -d/ -f1)"

    docker buildx inspect >/dev/null 2>&1 || docker buildx create --use

    docker buildx build \
      --platform linux/amd64 \
      -t "${ECR_URL}:${IMAGE_TAG}" \
      "${ROOT_DIR}/app" \
      --push
  fi
else
  echo "Skipping bootstrap image build. BUILD_BOOTSTRAP_IMAGE=false"
fi

echo "==> [8/11] Install ArgoCD"
kubectl create namespace argocd \
  --dry-run=client \
  -o yaml | kubectl apply -f -

kubectl apply --server-side=true \
  -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=Established \
  crd/applications.argoproj.io \
  --timeout=120s

kubectl rollout status deployment/argocd-repo-server \
  -n argocd \
  --timeout=300s

kubectl rollout status deployment/argocd-server \
  -n argocd \
  --timeout=300s

kubectl rollout status statefulset/argocd-application-controller \
  -n argocd \
  --timeout=300s

echo "==> [9/11] Apply ArgoCD Application"
kubectl apply -f "${ARGOCD_APP_PATH}"

kubectl annotate application olivesafety-dev \
  -n argocd \
  argocd.argoproj.io/refresh=hard \
  --overwrite

echo "Waiting for ArgoCD application to become Synced / Healthy..."
ARGOCD_READY=false

for i in {1..40}; do
  SYNC_STATUS="$(kubectl get application olivesafety-dev -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  HEALTH_STATUS="$(kubectl get application olivesafety-dev -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)"

  echo "ArgoCD status: ${SYNC_STATUS:-Unknown} / ${HEALTH_STATUS:-Unknown} (${i}/40)"

  if [[ "${SYNC_STATUS}" == "Synced" && "${HEALTH_STATUS}" == "Healthy" ]]; then
    ARGOCD_READY=true
    break
  fi

  sleep 15
done

if [[ "${ARGOCD_READY}" != "true" ]]; then
  echo "ERROR: ArgoCD application did not become Synced / Healthy."

  echo "Application conditions:"
  kubectl get application olivesafety-dev -n argocd \
    -o jsonpath='{range .status.conditions[*]}{.type}{" | "}{.message}{"\n"}{end}' || true

  echo "Application resources:"
  kubectl get application olivesafety-dev -n argocd \
    -o jsonpath='{range .status.resources[*]}{.kind}{" / "}{.name}{" / "}{.status}{" / "}{.health.status}{"\n"}{end}' || true

  echo "Pods in olivesafety namespace:"
  kubectl get pods -n olivesafety || true

  exit 1
fi

echo "==> [10/11] Verify application endpoint"
APP_ALB_DNS=""

echo "Waiting for ALB DNS..."
for i in {1..60}; do
  APP_ALB_DNS="$(kubectl get ingress olivesafety-api -n olivesafety -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"

  if [[ -n "${APP_ALB_DNS}" ]]; then
    break
  fi

  echo "Waiting for ALB DNS... ${i}/60"
  sleep 10
done

if [[ -z "${APP_ALB_DNS}" ]]; then
  echo "ERROR: ALB DNS not found"
  exit 1
fi

echo "ALB DNS: ${APP_ALB_DNS}"

echo "Health check:"
curl -s "http://${APP_ALB_DNS}/actuator/health" || true
echo

echo "==> [11/11] Refresh ALB/TG suffix and apply CloudWatch alarm dimensions"
ALB_ARN="$(aws elbv2 describe-load-balancers \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" \
  --query "LoadBalancers[?DNSName=='${APP_ALB_DNS}'].LoadBalancerArn | [0]" \
  --output text)"

if [[ -z "${ALB_ARN}" || "${ALB_ARN}" == "None" ]]; then
  echo "ERROR: Failed to find ALB ARN for DNS: ${APP_ALB_DNS}"
  exit 1
fi

TG_ARN="$(aws elbv2 describe-target-groups \
  --load-balancer-arn "${ALB_ARN}" \
  --region "${AWS_REGION}" \
  --profile "${AWS_PROFILE}" \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)"

if [[ -z "${TG_ARN}" || "${TG_ARN}" == "None" ]]; then
  echo "ERROR: Failed to find TargetGroup ARN for ALB: ${ALB_ARN}"
  exit 1
fi

ALB_ARN_SUFFIX="${ALB_ARN#*loadbalancer/}"
TG_ARN_SUFFIX="targetgroup/${TG_ARN#*targetgroup/}"

cat > "${TF_DIR}/alerting.auto.tfvars" <<ALERTING_TFVARS
enable_alb_alarms       = true
alb_arn_suffix          = "${ALB_ARN_SUFFIX}"
target_group_arn_suffix = "${TG_ARN_SUFFIX}"
ALERTING_TFVARS

echo "Generated ${TF_DIR}/alerting.auto.tfvars"
cat "${TF_DIR}/alerting.auto.tfvars"

if [[ "${RUN_FINAL_TERRAFORM_APPLY}" == "true" ]]; then
  cd "${TF_DIR}"
  terraform apply -auto-approve
  cd "${ROOT_DIR}"
else
  echo "Skipping final Terraform apply. RUN_FINAL_TERRAFORM_APPLY=false"
fi

echo
echo "NOTE: If you run Atlantis plan/apply after dev-up, update Bastion /opt/atlantis/tfvars/alerting.tfvars with the same ALB/TG values."
echo "==> Done"

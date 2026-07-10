# Runbook: IRSA Credentials Error

## 1. 상황

애플리케이션 Pod는 Running 상태이지만 AWS API 호출 시 다음 오류가 발생한다.

```text
Unable to load AWS credentials from any provider in the chain
WebIdentityTokenCredentialsProvider: You must specify a value for roleArn and roleSessionName
```

또는 AWS SDK v1 사용 시 다음 오류가 발생할 수 있다.

```text
To use assume role profiles the aws-java-sdk-sts module must be on the class path
```

## 2. 영향도

애플리케이션이 SQS, SNS, Secrets Manager 등 AWS API를 호출하지 못한다.

SQS polling, SNS publish 등 AWS 연동 기능이 실패한다.

## 3. 주요 원인

1. 애플리케이션 ServiceAccount에 IRSA annotation이 없음
2. Pod가 올바른 ServiceAccount를 사용하지 않음
3. IAM Role trust policy의 `sub` 조건이 ServiceAccount와 불일치함
4. AWS SDK v1에서 `aws-java-sdk-sts` 의존성이 누락됨
5. Pod가 annotation 적용 전에 생성되어 환경변수를 받지 못함

## 4. 확인 절차

ServiceAccount annotation 확인:

```bash
kubectl get sa olivesafety-api-sa -n olivesafety -o yaml | grep -A5 annotations
```

정상 예시:

```yaml
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::191524136560:role/olivesafety-day2-ops-dev-api-role
```

Deployment가 사용하는 ServiceAccount 확인:

```bash
kubectl get deployment olivesafety-api -n olivesafety \
  -o jsonpath='{.spec.template.spec.serviceAccountName}{"\n"}'
```

Pod 내부 IRSA 환경변수 확인:

```bash
POD_NAME=$(kubectl get pods -n olivesafety -l app=olivesafety-api -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n olivesafety $POD_NAME -- printenv | grep -E "AWS_ROLE_ARN|AWS_WEB_IDENTITY_TOKEN_FILE"
```

정상 예시:

```text
AWS_ROLE_ARN=arn:aws:iam::191524136560:role/olivesafety-day2-ops-dev-api-role
AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

앱 로그 확인:

```bash
kubectl logs -n olivesafety deployment/olivesafety-api --tail=200 \
  | grep -Ei "credentials|WebIdentity|AccessDenied|SQS|SNS"
```

## 5. 복구 절차

Terraform에서 앱용 IRSA Role 생성:

```bash
cd terraform/envs/dev
terraform apply
API_ROLE_ARN=$(terraform output -raw api_irsa_role_arn)
cd ../../..
```

ServiceAccount patch 파일 확인:

```bash
cat k8s/overlays/dev/serviceaccount-irsa-patch.yaml
```

정상 예시:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: olivesafety-api-sa
  namespace: olivesafety
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::191524136560:role/olivesafety-day2-ops-dev-api-role
```

Kubernetes manifest 적용:

```bash
kubectl apply -k k8s/overlays/dev
```

기존 Pod에는 annotation이 자동 반영되지 않으므로 Deployment를 재시작한다.

```bash
kubectl rollout restart deployment/olivesafety-api -n olivesafety
kubectl rollout status deployment/olivesafety-api -n olivesafety
```

AWS SDK v1 사용 시 `build.gradle`에 STS 의존성을 추가한다.

```gradle
implementation 'com.amazonaws:aws-java-sdk-sts:<aws-sdk-version>'
```

## 6. 정상 확인

IRSA 환경변수 확인:

```bash
POD_NAME=$(kubectl get pods -n olivesafety -l app=olivesafety-api -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n olivesafety $POD_NAME -- printenv | grep -E "AWS_ROLE_ARN|AWS_WEB_IDENTITY_TOKEN_FILE"
```

로그에서 다음 오류가 사라지면 IRSA 인증 문제는 해결된 것이다.

```text
Unable to load AWS credentials
```

## 7. 재발 방지

- ServiceAccount annotation을 Kustomize patch로 관리한다.
- 앱용 IAM Role은 최소 권한 정책으로 분리한다.
- AWS SDK v1 사용 시 STS 의존성을 명시한다.
- Pod 재시작 후 IRSA 환경변수 유무를 검증한다.

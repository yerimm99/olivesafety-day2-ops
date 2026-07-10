# Runbook: SQS QueueDoesNotExist

## 1. 상황

애플리케이션 로그에서 다음 오류가 발생한다.

```text
QueueDoesNotExistException: The specified queue does not exist
Error Code: AWS.SimpleQueueService.NonExistentQueue
```

## 2. 영향도

애플리케이션의 SQS polling 기능이 실패한다.

메시지 기반 비동기 처리 기능이 정상 동작하지 않는다.

## 3. 주요 원인

1. 앱이 참조하는 `AWS_SQS_URL`의 Queue가 실제로 존재하지 않음
2. Secrets Manager에 저장된 SQS URL이 잘못됨
3. External Secrets가 최신 값을 Kubernetes Secret으로 동기화하지 않음
4. Secret은 갱신됐지만 Pod가 재시작되지 않아 이전 환경변수를 사용 중임
5. 다른 Region의 SQS URL을 사용 중임

## 4. 확인 절차

Pod 환경변수 확인:

```bash
POD_NAME=$(kubectl get pods -n olivesafety -l app=olivesafety-api -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n olivesafety $POD_NAME -- printenv | grep -E "AWS_SQS_URL|AWS_SNS_ARN|AWS_REGION"
```

AWS 계정에 실제 Queue가 있는지 확인:

```bash
aws sqs list-queues \
  --region ap-northeast-2 \
  --profile yerim-admin
```

Terraform output 확인:

```bash
cd terraform/envs/dev
terraform output sqs_queue_url
terraform output sns_topic_arn
cd ../../..
```

Kubernetes Secret에 반영된 값 확인:

```bash
kubectl get secret olivesafety-api-secret -n olivesafety \
  -o jsonpath='{.data.AWS_SQS_URL}' | base64 -d
echo
```

## 5. 복구 절차

Terraform으로 SQS/SNS 리소스 생성:

```bash
cd terraform/envs/dev
terraform apply
cd ../../..
```

ExternalSecret 강제 동기화:

```bash
kubectl annotate externalsecret olivesafety-api-secret \
  -n olivesafety \
  force-sync=$(date +%s) \
  --overwrite
```

Secret 값 확인:

```bash
kubectl get secret olivesafety-api-secret -n olivesafety \
  -o jsonpath='{.data.AWS_SQS_URL}' | base64 -d
echo
```

Pod 재시작:

```bash
kubectl rollout restart deployment/olivesafety-api -n olivesafety
kubectl rollout status deployment/olivesafety-api -n olivesafety
```

## 6. 정상 확인

앱 로그 확인:

```bash
kubectl logs -n olivesafety deployment/olivesafety-api --tail=200 \
  | grep -Ei "QueueDoesNotExist|SQS|Unable to load|AccessDenied"
```

`QueueDoesNotExist` 오류가 더 이상 발생하지 않으면 정상이다.

## 7. 재발 방지

- SQS/SNS 리소스는 Terraform으로 생성하고 output으로 관리한다.
- Secrets Manager 값은 Terraform output 기반으로 갱신한다.
- Secret 변경 후에는 ExternalSecret 동기화와 Pod 재시작을 수행한다.
- Region과 Queue URL이 일치하는지 확인한다.

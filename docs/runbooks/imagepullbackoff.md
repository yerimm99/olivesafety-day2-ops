# Runbook: ImagePullBackOff

## 1. 상황

EKS에 애플리케이션 Pod를 배포했지만 Pod가 정상 기동되지 않고 다음 상태에 머무른다.

```text
ImagePullBackOff
ErrImagePull
```

## 2. 영향도

애플리케이션 컨테이너가 시작되지 않기 때문에 서비스가 정상 제공되지 않는다.

## 3. 주요 원인

가능한 원인은 다음과 같다.

1. ECR에 지정한 image tag가 존재하지 않음
2. EKS Node Role에 ECR pull 권한이 없음
3. Apple Silicon 환경에서 arm64 이미지로 빌드했지만 EKS Node는 amd64 아키텍처임
4. ECR repository URL 또는 image tag가 Kubernetes manifest와 불일치함

## 4. 확인 절차

Pod 상태 확인:

```bash
kubectl get pods -n olivesafety
```

Pod 이벤트 확인:

```bash
POD_NAME=$(kubectl get pods -n olivesafety -l app=olivesafety-api -o jsonpath='{.items[0].metadata.name}')

kubectl describe pod -n olivesafety $POD_NAME | sed -n '/Events/,$p'
```

Pod가 참조하는 이미지 확인:

```bash
kubectl get pod -n olivesafety $POD_NAME \
  -o jsonpath='{.spec.containers[0].image}{"\n"}'
```

ECR에 image tag가 존재하는지 확인:

```bash
aws ecr describe-images \
  --repository-name olivesafety-day2-ops-dev/olivesafety-api \
  --image-ids imageTag=dev-local \
  --region ap-northeast-2 \
  --profile yerim-admin
```

## 5. 복구 절차

ECR URL 확인:

```bash
cd terraform/envs/dev
ECR_URL=$(terraform output -raw ecr_repository_url)
cd ../../..
```

ECR 로그인:

```bash
aws ecr get-login-password \
  --region ap-northeast-2 \
  --profile yerim-admin \
  | docker login --username AWS --password-stdin $(echo $ECR_URL | cut -d/ -f1)
```

Apple Silicon 환경에서는 EKS Node 아키텍처와 맞추기 위해 `linux/amd64`로 빌드한다.

```bash
docker buildx build \
  --platform linux/amd64 \
  -t ${ECR_URL}:dev-local \
  ./app \
  --push
```

Deployment 재시작:

```bash
kubectl rollout restart deployment/olivesafety-api -n olivesafety
kubectl rollout status deployment/olivesafety-api -n olivesafety
```

## 6. 정상 확인

```bash
kubectl get pods -n olivesafety
```

정상 예시:

```text
olivesafety-api-xxxxx   1/1   Running
```

## 7. 재발 방지

- 이미지 빌드 시 `--platform linux/amd64` 옵션을 명시한다.
- CI/CD 적용 시 image tag를 commit SHA 기반으로 관리한다.
- Kubernetes manifest의 image tag와 ECR push tag를 일치시킨다.

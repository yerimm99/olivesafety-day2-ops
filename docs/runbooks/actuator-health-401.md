# Runbook: Actuator Health 401

## 1. 상황

Pod는 Running 상태이지만 Ready 상태가 되지 않는다.

```text
READY 0/1
```

Pod 이벤트에서 다음과 같은 메시지가 확인된다.

```text
Readiness probe failed: HTTP probe failed with statuscode: 401
Liveness probe failed: HTTP probe failed with statuscode: 401
```

## 2. 영향도

Kubernetes가 Pod를 정상 endpoint로 판단하지 못한다.

따라서 Service 또는 ALB Target Group에서 정상 대상으로 등록되지 않을 수 있다.

## 3. 주요 원인

Spring Security 또는 JWT Filter가 Kubernetes health check endpoint를 인증 대상으로 처리하는 경우 발생한다.

Kubernetes readiness/liveness probe는 인증 토큰 없이 다음 endpoint를 호출한다.

```text
/actuator/health/readiness
/actuator/health/liveness
```

이 요청이 인증 필터에 막히면 401이 반환된다.

## 4. 확인 절차

Pod 이벤트 확인:

```bash
POD_NAME=$(kubectl get pods -n olivesafety -l app=olivesafety-api -o jsonpath='{.items[0].metadata.name}')

kubectl describe pod -n olivesafety $POD_NAME | sed -n '/Events/,$p'
```

앱 로그 확인:

```bash
kubectl logs -n olivesafety $POD_NAME --tail=100
```

Deployment probe 설정 확인:

```bash
kubectl get deployment olivesafety-api -n olivesafety -o yaml | grep -A20 readinessProbe
```

## 5. 복구 절차

Spring Security 설정에서 actuator health endpoint를 인증 필터 대상에서 제외한다.

예시:

```java
@Bean
public WebSecurityCustomizer webSecurityCustomizer() {
    return (web) -> web.ignoring()
            .antMatchers(
                    "/favicon.ico",
                    "/health",
                    "/error",
                    "/",
                    "/api/member/login",
                    "/api/item",
                    "/actuator/health",
                    "/actuator/health/**"
            );
}
```

수정 후 애플리케이션을 다시 빌드하고 ECR에 push한다.

```bash
cd app
./gradlew clean build -x test
cd ..

cd terraform/envs/dev
ECR_URL=$(terraform output -raw ecr_repository_url)
cd ../../..

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

ALB health check 확인:

```bash
APP_ALB_DNS=$(kubectl get ingress olivesafety-api -n olivesafety -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl http://${APP_ALB_DNS}/actuator/health
```

정상 응답:

```json
{"status":"UP","groups":["liveness","readiness"]}
```

## 7. 재발 방지

- health endpoint는 인증 필터에서 제외한다.
- 운영 endpoint와 health endpoint의 보안 정책을 분리한다.
- readiness/liveness probe 변경 시 실제 HTTP status code를 반드시 확인한다.

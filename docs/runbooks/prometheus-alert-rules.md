# Prometheus Alert Rules Runbook

## 목적

이 문서는 `olivesafety-api` 애플리케이션에 적용한 Prometheus Alert Rule의 목적, 발생 조건, 확인 방법, 장애 대응 절차를 정리한 운영 런북이다.

현재 dev 환경에서는 `Alertmanager`를 비활성화한 상태이므로, Slack 또는 Email 알림 전송은 아직 수행하지 않는다.  
이번 단계의 목적은 Prometheus가 장애 조건을 Rule로 평가하고, Prometheus UI에서 `Pending` 또는 `Firing` 상태를 확인할 수 있도록 구성하는 것이다.

향후 Alertmanager 또는 CloudWatch Alarm + Lambda + Slack 연동을 추가하여 실제 알림 전송까지 확장할 수 있다.

## 구성 요소

| 구성 요소 | 역할 |
|---|---|
| Prometheus | 메트릭 수집 및 Alert Rule 평가 |
| PrometheusRule | Alert 조건 정의 |
| ServiceMonitor | `olivesafety-api` 메트릭 scrape 대상 정의 |
| kube-state-metrics | Pod restart 등 Kubernetes 상태 메트릭 제공 |
| Spring Boot Actuator | 애플리케이션 JVM/HTTP 메트릭 제공 |

## Alert Rule 목록

현재 `olivesafety-api`에 대해 다음 Alert Rule을 구성했다.

| Alert 이름 | 심각도 | 감지 대상 |
|---|---|---|
| `OliveSafetyApiTargetDown` | critical | Prometheus scrape target down |
| `OliveSafetyApiPodRestarted` | warning | Pod 재시작 발생 |
| `OliveSafetyApiHttp5xxDetected` | warning | HTTP 5xx 응답 발생 |
| `OliveSafetyApiHighJvmMemoryUsage` | warning | JVM Heap 메모리 사용률 80% 초과 |

## PrometheusRule 리소스

Alert Rule은 다음 Kubernetes 리소스로 관리한다.

~~~text
k8s/base/prometheusrule.yaml
~~~

리소스 확인:

~~~bash
kubectl get prometheusrule -n olivesafety
~~~

정상 예시:

~~~text
NAME                           AGE
olivesafety-api-alert-rules    10m
~~~

상세 확인:

~~~bash
kubectl describe prometheusrule -n olivesafety olivesafety-api-alert-rules
~~~

## Prometheus Rule 로딩 확인

Prometheus에 port-forward를 설정한다.

~~~bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
~~~

브라우저에서 Rule 목록을 확인한다.

~~~text
http://localhost:9090/rules
~~~

Alert 상태는 다음 화면에서 확인한다.

~~~text
http://localhost:9090/alerts
~~~

CLI로 확인하려면 다음 명령어를 사용한다.

~~~bash
curl -s "http://localhost:9090/api/v1/rules" \
| jq '.data.groups[]
  | select(.name == "olivesafety-api.rules")
  | {
      name: .name,
      rules: [.rules[].name]
    }'
~~~

정상 예시:

~~~json
{
  "name": "olivesafety-api.rules",
  "rules": [
    "OliveSafetyApiTargetDown",
    "OliveSafetyApiPodRestarted",
    "OliveSafetyApiHttp5xxDetected",
    "OliveSafetyApiHighJvmMemoryUsage"
  ]
}
~~~

## 1. OliveSafetyApiTargetDown

### 목적

`olivesafety-api`의 Prometheus scrape target이 내려간 상태를 감지한다.

애플리케이션 Pod가 죽었거나, ServiceMonitor 설정이 잘못되었거나, `/actuator/prometheus` endpoint가 정상 응답하지 않는 경우 발생할 수 있다.

### 조건

~~~promql
up{job=~".*olivesafety.*"} == 0
~~~

### 발생 기준

~~~text
2분 이상 target이 down 상태인 경우
~~~

### 확인 방법

Prometheus target 상태를 확인한다.

~~~bash
curl -s "http://localhost:9090/api/v1/targets?state=active" \
| jq '.data.activeTargets[]
  | select((.scrapePool // "" | contains("olivesafety")) or (.labels.job // "" | contains("olivesafety")))
  | {
      health: .health,
      scrapePool: .scrapePool,
      job: .labels.job,
      instance: .labels.instance,
      lastError: .lastError
    }'
~~~

ServiceMonitor 확인:

~~~bash
kubectl get servicemonitor -n olivesafety
~~~

Service label 확인:

~~~bash
kubectl get svc olivesafety-api -n olivesafety --show-labels
~~~

메트릭 endpoint 확인:

~~~bash
ALB_DNS=$(kubectl get ingress olivesafety-api -n olivesafety \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -I "http://${ALB_DNS}/actuator/prometheus"
~~~

### 대응 절차

1. `olivesafety-api` Pod 상태를 확인한다.
2. `/actuator/prometheus` endpoint가 200으로 응답하는지 확인한다.
3. ServiceMonitor selector와 Service label이 일치하는지 확인한다.
4. Prometheus target의 `lastError`를 확인한다.
5. 최근 배포 또는 설정 변경 이력을 확인한다.

## 2. OliveSafetyApiPodRestarted

### 목적

`olivesafety-api` Pod가 최근 10분 안에 재시작되었는지 감지한다.

Pod 재시작은 애플리케이션 예외, OOMKilled, probe 실패, 설정 오류, 외부 의존성 문제 등으로 발생할 수 있다.

### 조건

~~~promql
increase(kube_pod_container_status_restarts_total{namespace="olivesafety", pod=~"olivesafety-api.*"}[10m]) > 0
~~~

### 발생 기준

~~~text
최근 10분 동안 Pod restart count가 증가한 경우
~~~

### 확인 방법

Pod 상태 확인:

~~~bash
kubectl get pods -n olivesafety
~~~

Pod restart count 확인:

~~~bash
kubectl get pods -n olivesafety \
  -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[*].restartCount
~~~

Pod 이벤트 확인:

~~~bash
POD_NAME=$(kubectl get pod -n olivesafety \
  -l app.kubernetes.io/name=olivesafety-api \
  -o jsonpath='{.items[0].metadata.name}')

kubectl describe pod -n olivesafety "$POD_NAME" | sed -n '/Events/,$p'
~~~

애플리케이션 로그 확인:

~~~bash
kubectl logs -n olivesafety "$POD_NAME" --tail=200
~~~

이전 컨테이너 로그 확인:

~~~bash
kubectl logs -n olivesafety "$POD_NAME" --previous --tail=200
~~~

### 대응 절차

1. Pod restart 횟수와 발생 시간을 확인한다.
2. `describe pod`에서 `OOMKilled`, `Error`, `Failed`, `Unhealthy` 이벤트를 확인한다.
3. readiness/liveness probe 실패 여부를 확인한다.
4. 애플리케이션 로그에서 예외 발생 여부를 확인한다.
5. 최근 배포된 image tag와 변경사항을 확인한다.

## 3. OliveSafetyApiHttp5xxDetected

### 목적

`olivesafety-api`에서 HTTP 5xx 응답이 발생하는지 감지한다.

5xx는 애플리케이션 내부 예외, DB/Redis/SQS/SNS 등 외부 의존성 오류, 설정 누락, 인증/필터 예외 등으로 발생할 수 있다.

### 조건

~~~promql
sum(rate(http_server_requests_seconds_count{job=~".*olivesafety.*", status=~"5.."}[5m])) > 0
~~~

### 발생 기준

~~~text
최근 5분 동안 HTTP 5xx 응답이 1건 이상 발생한 경우
~~~

### 확인 방법

최근 HTTP status metric 확인:

~~~promql
sum by (status, uri, method) (
  rate(http_server_requests_seconds_count{job=~".*olivesafety.*"}[5m])
)
~~~

5xx 요청만 확인:

~~~promql
sum by (status, uri, method) (
  rate(http_server_requests_seconds_count{job=~".*olivesafety.*", status=~"5.."}[5m])
)
~~~

애플리케이션 로그 확인:

~~~bash
POD_NAME=$(kubectl get pod -n olivesafety \
  -l app.kubernetes.io/name=olivesafety-api \
  -o jsonpath='{.items[0].metadata.name}')

kubectl logs -n olivesafety "$POD_NAME" --tail=200
~~~

### 대응 절차

1. 5xx가 발생한 URI와 method를 확인한다.
2. 같은 시간대 애플리케이션 로그의 Exception을 확인한다.
3. DB, Redis, AWS SQS/SNS 등 외부 의존성 오류 여부를 확인한다.
4. 최근 배포나 설정 변경이 있었는지 확인한다.
5. 특정 endpoint에서만 발생하는지, 전체 endpoint에서 발생하는지 구분한다.

## 4. OliveSafetyApiHighJvmMemoryUsage

### 목적

`olivesafety-api` JVM Heap 메모리 사용률이 높아지는 상황을 감지한다.

Heap 사용률이 지속적으로 높으면 GC 증가, 응답 지연, OOMKilled로 이어질 수 있다.

### 조건

~~~promql
(
  sum(jvm_memory_used_bytes{job=~".*olivesafety.*", area="heap"})
  /
  sum(jvm_memory_max_bytes{job=~".*olivesafety.*", area="heap"})
) > 0.8
~~~

### 발생 기준

~~~text
JVM Heap 사용률이 5분 이상 80%를 초과한 경우
~~~

### 확인 방법

JVM Heap 사용률 확인:

~~~promql
sum(jvm_memory_used_bytes{job=~".*olivesafety.*", area="heap"})
/
sum(jvm_memory_max_bytes{job=~".*olivesafety.*", area="heap"})
~~~

Heap used 확인:

~~~promql
jvm_memory_used_bytes{job=~".*olivesafety.*", area="heap"}
~~~

Heap max 확인:

~~~promql
jvm_memory_max_bytes{job=~".*olivesafety.*", area="heap"}
~~~

Pod 메모리 사용량 확인:

~~~bash
kubectl top pod -n olivesafety
~~~

Pod resource 설정 확인:

~~~bash
kubectl get deploy olivesafety-api -n olivesafety -o yaml \
| sed -n '/resources:/,+20p'
~~~

### 대응 절차

1. JVM Heap 사용률이 일시적인지 지속적인지 확인한다.
2. 같은 시간대 HTTP 요청량 증가 여부를 확인한다.
3. Pod restart 또는 OOMKilled 이벤트가 있었는지 확인한다.
4. 메모리 limit과 JVM max heap 설정을 확인한다.
5. 필요 시 replica 증가, resource limit 조정, 메모리 누수 분석을 검토한다.

## 현재 dev 환경 기준 제한사항

현재 dev 환경에서는 비용과 리소스 절감을 위해 일부 기능을 비활성화했다.

~~~text
Alertmanager: disabled
nodeExporter: disabled
~~~

따라서 현재 단계에서는 Alert Rule이 Prometheus UI에서 `Inactive`, `Pending`, `Firing` 상태로 평가되는지 확인하는 데 목적이 있다.

실제 Slack 알림 전송은 이후 단계에서 다음 중 하나로 확장한다.

~~~text
1. Alertmanager + Slack Receiver
2. CloudWatch Alarm + Lambda + Slack
~~~

## 검증 체크리스트

| 항목 | 확인 명령어 |
|---|---|
| PrometheusRule 생성 여부 | `kubectl get prometheusrule -n olivesafety` |
| Prometheus Rule 로딩 여부 | `http://localhost:9090/rules` |
| Alert 상태 확인 | `http://localhost:9090/alerts` |
| 애플리케이션 target 상태 | `up{job=~".*olivesafety.*"}` |
| Pod restart metric | `kube_pod_container_status_restarts_total` |
| HTTP 5xx metric | `http_server_requests_seconds_count{status=~"5.."}` |
| JVM heap metric | `jvm_memory_used_bytes`, `jvm_memory_max_bytes` |

## 현재 구성 요약

현재 dev 환경에서는 `olivesafety-api`에 대해 다음 장애 조건을 Prometheus Alert Rule로 정의했다.

~~~text
Prometheus target down
Pod restart 발생
HTTP 5xx 응답 발생
JVM Heap 메모리 사용률 80% 초과
~~~

이를 통해 애플리케이션 상태를 단순 조회하는 수준을 넘어, 운영 중 장애 징후를 Prometheus가 지속적으로 평가할 수 있는 기반을 구성했다.

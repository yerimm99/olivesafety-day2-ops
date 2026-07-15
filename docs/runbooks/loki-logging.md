# Loki Logging Runbook

## 목적

이 문서는 `olivesafety-api` 애플리케이션 로그를 Loki로 수집하고 Grafana에서 조회하는 방법을 정리한 운영 런북이다.

이번 구성의 목적은 Prometheus 기반 메트릭 관측에 더해, 장애 발생 시 애플리케이션 로그를 함께 확인할 수 있는 로그 관측 환경을 구성하는 것이다.

## 구성 요소

| 구성 요소 | 역할 |
|---|---|
| Loki | 로그 저장 및 조회 백엔드 |
| Loki Gateway | Loki API 접근을 위한 Gateway |
| Grafana Alloy | Kubernetes Pod 로그 수집 Agent |
| Grafana | Loki datasource를 통한 로그 조회 |
| LogQL | Loki 로그 조회 쿼리 언어 |

## 현재 구성 방식

현재 dev 환경에서는 비용과 리소스 절감을 위해 Loki를 단일 인스턴스 방식으로 구성한다.

~~~text
Loki deployment mode: Monolithic
Replica: 1
Storage: filesystem
Persistence: disabled
~~~

이 구성은 운영용 HA 구성이 아니라, dev 환경에서 로그 수집과 조회 흐름을 검증하기 위한 경량 구성이다.

## Kubernetes 리소스 확인

Loki Pod 확인:

~~~bash
kubectl get pods -n monitoring | grep loki
~~~

정상 예시:

~~~text
loki-0                 2/2 Running
loki-gateway-xxxxx     2/2 Running
~~~

Loki Service 확인:

~~~bash
kubectl get svc -n monitoring | grep loki
~~~

정상 예시:

~~~text
loki                  ClusterIP   ...   3100/TCP
loki-gateway          ClusterIP   ...   80/TCP
~~~

Alloy Pod 확인:

~~~bash
kubectl get pods -n monitoring | grep alloy
~~~

Alloy DaemonSet 확인:

~~~bash
kubectl get daemonset -n monitoring | grep alloy
~~~

## Loki 상태 확인

Loki Gateway는 nginx 기반 gateway이므로 `/ready` 경로가 404를 반환할 수 있다.

Loki readiness를 직접 확인하려면 `loki` Service로 port-forward 한다.

~~~bash
kubectl port-forward -n monitoring svc/loki 3101:3100
~~~

다른 터미널에서 확인:

~~~bash
curl -s http://localhost:3101/ready
~~~

정상 응답:

~~~text
ready
~~~

Gateway를 통해 API 상태를 확인하려면 다음을 사용한다.

~~~bash
kubectl port-forward -n monitoring svc/loki-gateway 3100:80
~~~

다른 터미널에서 확인:

~~~bash
curl -s http://localhost:3100/loki/api/v1/status/buildinfo | jq
~~~

간단 쿼리 확인:

~~~bash
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query=vector(1)' | jq
~~~

## Alloy 로그 수집 확인

Alloy 로그를 확인한다.

~~~bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=100
~~~

에러 없이 Loki로 로그를 전송하고 있어야 한다.

Alloy는 Kubernetes Pod 로그를 수집하여 Loki Gateway로 전달한다.

~~~text
Kubernetes Pod Logs
→ Grafana Alloy
→ Loki Gateway
→ Loki
→ Grafana Explore
~~~

## Loki Label 확인

Loki에 수집된 label 목록을 확인한다.

~~~bash
curl -s "http://localhost:3100/loki/api/v1/labels" | jq
~~~

namespace label 값을 확인한다.

~~~bash
curl -s "http://localhost:3100/loki/api/v1/label/namespace/values" | jq
~~~

정상적으로 로그가 수집되면 다음 namespace들이 보일 수 있다.

~~~text
olivesafety
monitoring
argocd
external-secrets
~~~

## 애플리케이션 로그 조회

`olivesafety` namespace 로그를 조회한다.

~~~bash
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={namespace="olivesafety"}' \
  --data-urlencode 'limit=20' \
  | jq '.data.result[]?.values[]?'
~~~

`olivesafety-api` Pod 로그만 조회한다.

~~~bash
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={namespace="olivesafety", pod=~"olivesafety-api.*"}' \
  --data-urlencode 'limit=20' \
  | jq '.data.result[]?.values[]?'
~~~

## Grafana에서 로그 확인

Grafana에 접속한다.

~~~bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
~~~

브라우저에서 접속:

~~~text
http://localhost:3000
~~~

Grafana에서 다음 순서로 확인한다.

~~~text
Explore
→ Data source: Loki
→ LogQL 입력
~~~

기본 LogQL:

~~~logql
{namespace="olivesafety"}
~~~

`olivesafety-api` 로그 조회:

~~~logql
{namespace="olivesafety", pod=~"olivesafety-api.*"}
~~~

특정 문자열 검색:

~~~logql
{namespace="olivesafety", pod=~"olivesafety-api.*"} |= "ERROR"
~~~

예외 로그 검색:

~~~logql
{namespace="olivesafety", pod=~"olivesafety-api.*"} |= "Exception"
~~~

## 장애 상황별 확인 방법

### 1. Loki Pod가 Running이 아닌 경우

~~~bash
kubectl get pods -n monitoring | grep loki
kubectl describe pod -n monitoring loki-0
kubectl logs -n monitoring loki-0 --tail=100
~~~

확인할 항목:

~~~text
ImagePullBackOff
CrashLoopBackOff
Pending
Storage 관련 오류
Config validation 오류
~~~

### 2. Alloy Pod가 Pending인 경우

~~~bash
kubectl get pods -n monitoring | grep alloy
kubectl describe pod -n monitoring <ALLOY_POD_NAME>
~~~

확인할 항목:

~~~text
Too many pods
Insufficient cpu
Insufficient memory
NodeAffinity 문제
~~~

dev 환경에서는 Pod 수 제한으로 인해 노드를 2대로 유지해야 할 수 있다.

### 3. Grafana에서 Loki datasource가 안 보이는 경우

Grafana values에 Loki datasource가 추가되어 있는지 확인한다.

~~~bash
grep -A15 "additionalDataSources" observability/kube-prometheus-stack-values.yaml
~~~

Grafana Helm release를 다시 반영한다.

~~~bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f observability/kube-prometheus-stack-values.yaml \
  --wait \
  --timeout 10m
~~~

### 4. Loki에는 접속되지만 로그가 안 보이는 경우

Alloy 로그를 확인한다.

~~~bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=100
~~~

Loki label을 확인한다.

~~~bash
curl -s "http://localhost:3100/loki/api/v1/labels" | jq
curl -s "http://localhost:3100/loki/api/v1/label/namespace/values" | jq
~~~

조회하려는 namespace가 Alloy relabel 설정에 포함되어 있는지 확인한다.

~~~text
olivesafety
argocd
monitoring
external-secrets
~~~

### 5. `/ready`가 404를 반환하는 경우

`loki-gateway`는 nginx gateway이므로 `/ready`가 404를 반환할 수 있다.

Loki readiness는 `loki` Service로 직접 확인한다.

~~~bash
kubectl port-forward -n monitoring svc/loki 3101:3100
curl -s http://localhost:3101/ready
~~~

## 현재 구성 요약

현재 dev 환경에서는 다음 구성이 완료되어 있다.

~~~text
Loki monolithic single replica 설치
Loki Gateway 구성
Grafana Alloy DaemonSet 기반 Pod 로그 수집
Grafana Loki datasource 추가
olivesafety-api 로그 조회 확인
LogQL 기반 애플리케이션 로그 검색 가능
~~~

이를 통해 EKS 환경에서 메트릭은 Prometheus로, 로그는 Loki로 확인할 수 있는 기본 Observability 구조를 구성했다.

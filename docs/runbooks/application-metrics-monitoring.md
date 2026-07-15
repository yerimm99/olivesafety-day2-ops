# Application Metrics Monitoring Runbook

## 목적

이 문서는 `olivesafety-api` 애플리케이션의 Prometheus 메트릭 노출 방식과, Prometheus가 `ServiceMonitor`를 통해 해당 메트릭을 수집하는 구조를 정리한 운영 런북이다.

이번 구성의 목적은 단순히 Prometheus와 Grafana를 설치하는 것이 아니라, EKS에 배포된 Spring Boot 애플리케이션의 JVM, HTTP 요청, 프로세스 관련 메트릭을 Prometheus로 수집하고 Grafana에서 확인할 수 있는 관측 환경을 구성하는 것이다.

## 구성 요소

| 구성 요소 | 역할 |
|---|---|
| Spring Boot Actuator | 애플리케이션 상태 및 메트릭 endpoint 제공 |
| Micrometer Prometheus Registry | Spring Boot 메트릭을 Prometheus 형식으로 변환 |
| kube-prometheus-stack | Prometheus, Grafana, Prometheus Operator 구성 |
| ServiceMonitor | Prometheus가 수집할 Kubernetes Service와 endpoint 정의 |
| Grafana | Prometheus 메트릭 시각화 |

## 메트릭 노출 Endpoint

애플리케이션은 다음 endpoint를 통해 Prometheus 형식의 메트릭을 노출한다.

~~~text
/actuator/prometheus
~~~

정상 응답 예시는 다음과 같다.

~~~text
# HELP jvm_memory_used_bytes ...
# TYPE jvm_memory_used_bytes gauge
# HELP http_server_requests_seconds ...
# TYPE http_server_requests_seconds summary
~~~

JSON 응답이 아니라 `# HELP`, `# TYPE` 형태의 텍스트 메트릭이 반환되어야 한다.

## 애플리케이션 설정

### Prometheus 의존성

Spring Boot Actuator 메트릭을 Prometheus 형식으로 노출하기 위해 `micrometer-registry-prometheus` 의존성을 추가한다.

~~~gradle
implementation 'io.micrometer:micrometer-registry-prometheus'
~~~

### Actuator endpoint 노출 설정

`application.yml`에서 `prometheus` endpoint를 노출 대상에 포함한다.

~~~yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  endpoint:
    health:
      probes:
        enabled: true
    prometheus:
      enabled: true
~~~

`prometheus`가 빠져 있으면 `/actuator/prometheus` endpoint가 정상적으로 노출되지 않는다.

## Security / JWT Filter 설정

Prometheus는 별도의 인증 토큰 없이 `/actuator/prometheus` endpoint를 scrape한다.

따라서 Spring Security 또는 JWT Filter에서 다음 endpoint는 인증 없이 접근 가능하도록 예외 처리해야 한다.

~~~text
/actuator/health
/actuator/health/**
/actuator/prometheus
/actuator/prometheus/**
~~~

JWT Filter를 사용하는 경우 `permitAll()` 설정만으로는 부족할 수 있다.  
커스텀 필터가 먼저 실행되면 토큰 검증 과정에서 401 또는 500 오류가 발생할 수 있으므로, 필터 내부에서도 `/actuator/prometheus` 요청을 제외해야 한다.

예시:

~~~java
@Override
protected boolean shouldNotFilter(HttpServletRequest request) {
    String path = request.getRequestURI();

    return path.startsWith("/actuator/health")
            || path.startsWith("/actuator/prometheus");
}
~~~

또는 `doFilterInternal()` 초반에 다음과 같이 처리할 수 있다.

~~~java
String path = request.getRequestURI();

if (path.startsWith("/actuator/health")
        || path.startsWith("/actuator/prometheus")) {
    filterChain.doFilter(request, response);
    return;
}
~~~

## Kubernetes Service 설정

`ServiceMonitor`는 Pod가 아니라 Kubernetes `Service`의 label을 기준으로 scrape 대상을 찾는다.

따라서 `olivesafety-api` Service에는 다음 label이 필요하다.

~~~yaml
apiVersion: v1
kind: Service
metadata:
  name: olivesafety-api
  namespace: olivesafety
  labels:
    app.kubernetes.io/name: olivesafety-api
spec:
  selector:
    app.kubernetes.io/name: olivesafety-api
  ports:
    - name: http
      port: 80
      targetPort: 8080
~~~

중요한 부분은 다음 두 가지다.

~~~yaml
labels:
  app.kubernetes.io/name: olivesafety-api
~~~

~~~yaml
ports:
  - name: http
~~~

`ServiceMonitor`의 selector와 endpoint port가 이 값들을 기준으로 동작하기 때문이다.

## ServiceMonitor 설정

`ServiceMonitor`는 Prometheus Operator가 사용하는 리소스다.  
어떤 Service의 어떤 endpoint를 Prometheus가 수집할지 정의한다.

~~~yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: olivesafety-api
  namespace: olivesafety
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: olivesafety-api
  namespaceSelector:
    matchNames:
      - olivesafety
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 30s
      scrapeTimeout: 10s
~~~

위 설정은 다음 의미를 가진다.

| 항목 | 의미 |
|---|---|
| `selector.matchLabels` | 해당 label을 가진 Service를 scrape 대상으로 선택 |
| `namespaceSelector.matchNames` | `olivesafety` namespace의 Service를 대상으로 지정 |
| `endpoints.port` | Service port 이름 |
| `endpoints.path` | Prometheus 메트릭 endpoint |
| `interval` | scrape 주기 |
| `scrapeTimeout` | scrape timeout |

## Prometheus 설정

Prometheus가 `monitoring` namespace뿐 아니라 다른 namespace의 `ServiceMonitor`도 감지할 수 있어야 한다.

`kube-prometheus-stack-values.yaml`의 `prometheus.prometheusSpec` 아래에 다음 설정이 필요하다.

~~~yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelector: {}
    serviceMonitorNamespaceSelector: {}
~~~

이 설정이 없으면 `olivesafety` namespace에 생성한 `ServiceMonitor`가 Prometheus target으로 잡히지 않을 수 있다.

## 확인 절차

### 1. ServiceMonitor 확인

~~~bash
kubectl get servicemonitor -n olivesafety
~~~

정상 예시:

~~~text
NAME              AGE
olivesafety-api   10m
~~~

### 2. Service label 확인

~~~bash
kubectl get svc olivesafety-api -n olivesafety --show-labels
~~~

정상 예시:

~~~text
NAME              TYPE        CLUSTER-IP      PORT(S)   LABELS
olivesafety-api   ClusterIP   172.20.x.x      80/TCP    app.kubernetes.io/name=olivesafety-api
~~~

### 3. ALB를 통한 `/actuator/prometheus` 확인

~~~bash
ALB_DNS=$(kubectl get ingress olivesafety-api -n olivesafety \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -I "http://${ALB_DNS}/actuator/prometheus"
~~~

정상 예시:

~~~text
HTTP/1.1 200
~~~

응답 내용 확인:

~~~bash
curl -s "http://${ALB_DNS}/actuator/prometheus" | head -30
~~~

정상 예시:

~~~text
# HELP jvm_memory_used_bytes ...
# TYPE jvm_memory_used_bytes gauge
# HELP process_cpu_usage ...
~~~

## Prometheus Target 확인

Prometheus에 port-forward를 설정한다.

~~~bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
~~~

브라우저에서 다음 주소로 접속한다.

~~~text
http://localhost:9090/targets
~~~

`olivesafety-api` 또는 다음 형태의 target이 `UP` 상태인지 확인한다.

~~~text
serviceMonitor/olivesafety/olivesafety-api/0
~~~

CLI로 확인하려면 다음 명령어를 사용한다.

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

정상 예시:

~~~json
{
  "health": "up",
  "scrapePool": "serviceMonitor/olivesafety/olivesafety-api/0",
  "job": "olivesafety-api",
  "instance": "172.20.x.x:80",
  "lastError": ""
}
~~~

## 유용한 PromQL

### 애플리케이션 target 상태

~~~promql
up{job=~".*olivesafety.*"}
~~~

### JVM 메모리 사용량

~~~promql
jvm_memory_used_bytes
~~~

### HTTP 요청 수

~~~promql
http_server_requests_seconds_count
~~~

### HTTP 요청 지연 시간

~~~promql
rate(http_server_requests_seconds_sum[5m])
/
rate(http_server_requests_seconds_count[5m])
~~~

### 프로세스 CPU 사용률

~~~promql
process_cpu_usage
~~~

## Grafana 확인

Grafana에 접속한다.

~~~bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
~~~

브라우저에서 다음 주소로 접속한다.

~~~text
http://localhost:3000
~~~

기본 로그인 정보는 dev 환경 기준 다음과 같다.

~~~text
ID: admin
PW: admin
~~~

확인할 항목은 다음과 같다.

| 항목 | 확인 내용 |
|---|---|
| Prometheus datasource | 정상 연결 여부 |
| Kubernetes dashboard | Pod, Deployment, Namespace 상태 |
| Application metrics | JVM memory, HTTP request count, process CPU |
| Target 상태 | `olivesafety-api` target UP 여부 |

## 장애 상황별 확인 방법

### 1. `/actuator/prometheus`가 404를 반환하는 경우

Actuator exposure 설정에 `prometheus`가 포함되어 있는지 확인한다.

~~~yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
~~~

### 2. `/actuator/prometheus`가 401을 반환하는 경우

Spring Security에서 `/actuator/prometheus`가 인증 예외 처리되어 있는지 확인한다.

~~~text
/actuator/prometheus
/actuator/prometheus/**
~~~

### 3. `/actuator/prometheus`가 500을 반환하는 경우

JWT Filter 또는 공통 예외 처리 로직에서 `/actuator/prometheus` 요청을 가로채는지 확인한다.

Pod 로그를 확인한다.

~~~bash
POD_NAME=$(kubectl get pod -n olivesafety \
  -l app.kubernetes.io/name=olivesafety-api \
  -o jsonpath='{.items[0].metadata.name}')

kubectl logs -n olivesafety "$POD_NAME" --tail=150
~~~

### 4. ServiceMonitor는 있는데 Prometheus target이 안 보이는 경우

Prometheus가 다른 namespace의 ServiceMonitor를 감지하도록 설정되어 있는지 확인한다.

~~~bash
kubectl get prometheus -n monitoring kube-prometheus-stack-prometheus -o yaml \
| grep -A30 -E "serviceMonitorSelector|serviceMonitorNamespaceSelector"
~~~

정상 설정:

~~~yaml
serviceMonitorSelector: {}
serviceMonitorNamespaceSelector: {}
~~~

### 5. ServiceMonitor target이 DOWN인 경우

ServiceMonitor의 port 이름과 Service의 port 이름이 일치하는지 확인한다.

Service:

~~~yaml
ports:
  - name: http
~~~

ServiceMonitor:

~~~yaml
endpoints:
  - port: http
~~~

또한 `/actuator/prometheus` endpoint가 200으로 응답하는지 확인한다.

~~~bash
curl -I "http://${ALB_DNS}/actuator/prometheus"
~~~

## 현재 구성 요약

현재 dev 환경에서는 다음 구성이 완료되어 있다.

~~~text
Spring Boot Actuator Prometheus endpoint 활성화
Micrometer Prometheus Registry 적용
Security/JWT Filter에서 /actuator/prometheus 예외 처리
Kubernetes Service label 추가
ServiceMonitor 생성
Prometheus target UP 확인
JVM / HTTP / Process metric 수집 확인
~~~

이를 통해 EKS에 배포된 Spring Boot 애플리케이션의 주요 런타임 메트릭을 Prometheus 기반으로 수집하고 Grafana에서 확인할 수 있는 관측 환경을 구성했다.

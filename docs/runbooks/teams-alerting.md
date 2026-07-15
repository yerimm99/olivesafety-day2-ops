# Teams Alerting Runbook

## 목적

이 문서는 CloudWatch Alarm을 Microsoft Teams로 전달하는 알림 자동화 구조와 검증 절차를 정리한 운영 런북이다.

이번 구성의 목적은 AWS 리소스에서 장애성 조건이 발생했을 때 CloudWatch Alarm이 이를 감지하고, SNS와 Lambda를 통해 Microsoft Teams 채널로 알림을 전송하는 자동화 흐름을 구성하는 것이다.

## 전체 알림 흐름

현재 dev 환경의 알림 흐름은 다음과 같다.

~~~text
CloudWatch Alarm
→ SNS Topic
→ Lambda Teams Forwarder
→ AWS Secrets Manager에서 Teams Webhook URL 조회
→ Microsoft Teams 알림 전송
~~~

## 구성 요소

| 구성 요소 | 역할 |
|---|---|
| CloudWatch Alarm | AWS 리소스 상태 또는 메트릭 이상 감지 |
| SNS Topic | Alarm 이벤트를 Lambda로 전달 |
| Lambda Teams Forwarder | SNS 메시지를 Teams Webhook payload로 변환 후 전송 |
| AWS Secrets Manager | Teams Webhook URL 보관 |
| Microsoft Teams Workflow Webhook | Teams 채널 알림 수신 endpoint |

## Secret 구성

Teams Webhook URL은 민감정보이므로 Git, Terraform 코드, tfvars에 직접 저장하지 않는다.

현재 Secret 이름은 다음과 같다.

~~~text
olivesafety/dev/teams-webhook
~~~

Secret 값은 다음 구조로 저장한다.

~~~json
{
  "WEBHOOK_URL": "Teams Workflow Webhook URL"
}
~~~

Secret 저장 여부 확인:

~~~bash
aws secretsmanager get-secret-value \
  --secret-id "olivesafety/dev/teams-webhook" \
  --region ap-northeast-2 \
  --profile yerim-admin \
  --query SecretString \
  --output text \
| python3 -c 'import sys,json; data=json.load(sys.stdin); print("WEBHOOK_URL exists:", bool(data.get("WEBHOOK_URL")))'
~~~

정상 예시:

~~~text
WEBHOOK_URL exists: True
~~~

## Lambda 구성

Lambda 함수는 SNS 이벤트를 받아 CloudWatch Alarm 메시지를 파싱한 뒤 Teams Webhook으로 전달한다.

Lambda 코드 위치:

~~~text
lambda/teams-alert-forwarder/lambda_function.py
~~~

Terraform 리소스 위치:

~~~text
terraform/envs/dev/teams-alerting.tf
~~~

Lambda 이름 확인:

~~~bash
cd terraform/envs/dev
terraform output -raw teams_alert_lambda_name
cd ../../..
~~~

SNS Topic ARN 확인:

~~~bash
cd terraform/envs/dev
terraform output -raw teams_alert_sns_topic_arn
cd ../../..
~~~

## CloudWatch Alarm 구성

CloudWatch Alarm 정의 파일:

~~~text
terraform/envs/dev/cloudwatch-alarms.tf
~~~

현재 구성한 Alarm은 다음과 같다.

| Alarm 이름 | 감지 대상 |
|---|---|
| `olivesafety-day2-ops-dev-teams-alert-forwarder-errors` | Teams Forwarder Lambda Error |
| `olivesafety-day2-ops-dev-alb-unhealthy-targets` | ALB Target Unhealthy |
| `olivesafety-day2-ops-dev-alb-target-5xx` | ALB Target 5xx 응답 |

Alarm 목록 확인:

~~~bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "olivesafety-day2-ops-dev" \
  --region ap-northeast-2 \
  --profile yerim-admin \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Metric:MetricName}' \
  --output table
~~~

## ALB Alarm Dimension 주의사항

CloudWatch의 `AWS/ApplicationELB` 메트릭은 ALB 이름이나 TargetGroup 이름만 사용하는 것이 아니라, ARN suffix 형식의 dimension 값을 사용한다.

ALB dimension은 다음 형식이어야 한다.

~~~text
app/<load-balancer-name>/<load-balancer-id>
~~~

TargetGroup dimension은 반드시 `targetgroup/` prefix를 포함해야 한다.

~~~text
targetgroup/<target-group-name>/<target-group-id>
~~~

예시:

~~~bash
ALB_ARN_SUFFIX="${ALB_ARN#*loadbalancer/}"
TG_ARN_SUFFIX="targetgroup/${TG_ARN#*targetgroup/}"
~~~

주의할 점은 다음과 같다.

~~~text
잘못된 TargetGroup dimension:
k8s-olivesaf-olivesaf-xxxx/yyyy

정상 TargetGroup dimension:
targetgroup/k8s-olivesaf-olivesaf-xxxx/yyyy
~~~

`targetgroup/` prefix가 빠지면 Target이 실제로 unhealthy 상태여도 CloudWatch Alarm은 datapoint를 받지 못한다.

이 경우 Alarm 상태 Reason에 다음과 유사한 메시지가 표시될 수 있다.

~~~text
no datapoints were received
missing datapoints were treated as [NonBreaching]
~~~

## ALB / TargetGroup dimension 값 추출

현재 Ingress가 사용하는 ALB DNS를 조회한다.

~~~bash
export AWS_PROFILE="yerim-admin"
export AWS_REGION="ap-northeast-2"

ALB_DNS=$(kubectl get ingress olivesafety-api -n olivesafety \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "$ALB_DNS"
~~~

ALB ARN 조회:

~~~bash
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query "LoadBalancers[?DNSName=='${ALB_DNS}'].LoadBalancerArn | [0]" \
  --output text)

echo "$ALB_ARN"
~~~

TargetGroup ARN 조회:

~~~bash
TG_ARN=$(aws elbv2 describe-target-groups \
  --load-balancer-arn "$ALB_ARN" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

echo "$TG_ARN"
~~~

CloudWatch dimension suffix 생성:

~~~bash
ALB_ARN_SUFFIX="${ALB_ARN#*loadbalancer/}"
TG_ARN_SUFFIX="targetgroup/${TG_ARN#*targetgroup/}"

echo "$ALB_ARN_SUFFIX"
echo "$TG_ARN_SUFFIX"
~~~

## alerting.auto.tfvars

ALB와 TargetGroup은 Ingress 재생성 시 값이 바뀔 수 있다.

따라서 동적 dimension 값은 로컬 전용 tfvars 파일로 관리한다.

~~~text
terraform/envs/dev/alerting.auto.tfvars
~~~

예시:

~~~hcl
enable_alb_alarms       = true
alb_arn_suffix          = "app/k8s-.../..."
target_group_arn_suffix = "targetgroup/k8s-.../..."
~~~

이 파일은 환경별 동적 값이므로 Git에 커밋하지 않는다.

`.gitignore`에 다음 항목을 추가한다.

~~~text
terraform/envs/dev/alerting.auto.tfvars
~~~

## 수동 SNS 알림 테스트

CloudWatch Alarm 없이 SNS Topic에 직접 메시지를 발행하여 Teams 알림 흐름을 테스트할 수 있다.

~~~bash
cd terraform/envs/dev

TEAMS_TOPIC_ARN=$(terraform output -raw teams_alert_sns_topic_arn)
TEAMS_LAMBDA_NAME=$(terraform output -raw teams_alert_lambda_name)

cd ../../..
~~~

테스트 메시지 발송:

~~~bash
aws sns publish \
  --topic-arn "$TEAMS_TOPIC_ARN" \
  --subject "OliveSafety Test Alarm" \
  --message '{
    "AlarmName": "OliveSafety-Test-Alarm",
    "AWSAccountId": "191524136560",
    "NewStateValue": "ALARM",
    "OldStateValue": "OK",
    "NewStateReason": "Manual SNS test for Teams alert forwarding.",
    "StateChangeTime": "2026-07-15T00:00:00.000+0000",
    "Region": "Asia Pacific (Seoul)"
  }' \
  --region ap-northeast-2 \
  --profile yerim-admin
~~~

Teams 채널에 알림이 도착하면 다음 흐름이 정상이다.

~~~text
SNS
→ Lambda
→ Secrets Manager
→ Teams Webhook
~~~

## CloudWatch Alarm 수동 상태 변경 테스트

CloudWatch Alarm 상태를 강제로 변경하여 Alarm Action이 정상 동작하는지 확인할 수 있다.

Lambda Error Alarm을 ALARM 상태로 변경:

~~~bash
aws cloudwatch set-alarm-state \
  --alarm-name "olivesafety-day2-ops-dev-teams-alert-forwarder-errors" \
  --state-value ALARM \
  --state-reason "Manual test for Teams alert notification path." \
  --region ap-northeast-2 \
  --profile yerim-admin
~~~

OK 상태로 원복:

~~~bash
aws cloudwatch set-alarm-state \
  --alarm-name "olivesafety-day2-ops-dev-teams-alert-forwarder-errors" \
  --state-value OK \
  --state-reason "Manual recovery test for Teams alert notification path." \
  --region ap-northeast-2 \
  --profile yerim-admin
~~~

## ALB Target Unhealthy 테스트

ALB Target Unhealthy Alarm은 Ingress의 health check path를 임시로 잘못된 경로로 변경하여 검증할 수 있다.

현재 health check path 확인:

~~~bash
kubectl get ingress olivesafety-api -n olivesafety \
  -o jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/healthcheck-path}'; echo
~~~

원래 값 백업:

~~~bash
ORIGINAL_HEALTHCHECK_PATH=$(kubectl get ingress olivesafety-api -n olivesafety \
  -o jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/healthcheck-path}')

echo "$ORIGINAL_HEALTHCHECK_PATH"
~~~

잘못된 health check path 적용:

~~~bash
kubectl annotate ingress olivesafety-api -n olivesafety \
  alb.ingress.kubernetes.io/healthcheck-path=/invalid-healthcheck \
  --overwrite
~~~

Target 상태 확인:

~~~bash
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason,Description:TargetHealth.Description}' \
  --output table
~~~

반복 확인이 필요한 경우 macOS에서는 `watch` 대신 다음 while loop를 사용한다.

~~~bash
while true; do
  clear
  date
  aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason,Description:TargetHealth.Description}' \
    --output table
  sleep 15
done
~~~

정상적으로 장애가 유발되면 Target 상태가 다음과 같이 변경된다.

~~~text
State: unhealthy
Reason: Target.ResponseCodeMismatch
~~~

Alarm 상태 확인:

~~~bash
aws cloudwatch describe-alarms \
  --alarm-names "olivesafety-day2-ops-dev-alb-unhealthy-targets" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Reason:StateReason}' \
  --output table
~~~

CloudWatch Alarm이 `ALARM`으로 전환되고 Teams 알림이 도착하면 검증 성공이다.

## ALB Health Check 원복

테스트 후에는 반드시 health check path를 원복한다.

~~~bash
kubectl annotate ingress olivesafety-api -n olivesafety \
  alb.ingress.kubernetes.io/healthcheck-path="${ORIGINAL_HEALTHCHECK_PATH:-/actuator/health}" \
  --overwrite
~~~

원복 확인:

~~~bash
kubectl get ingress olivesafety-api -n olivesafety \
  -o jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/healthcheck-path}'; echo
~~~

정상 값:

~~~text
/actuator/health
~~~

Target 상태가 healthy로 돌아오는지 확인:

~~~bash
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason}' \
  --output table
~~~

정상 예시:

~~~text
State: healthy
~~~

## ALB Target 5xx Alarm 테스트

애플리케이션에 의도적으로 500을 반환하는 테스트 endpoint가 있는 경우 해당 endpoint를 호출하여 검증할 수 있다.

~~~bash
ALB_DNS=$(kubectl get ingress olivesafety-api -n olivesafety \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

for i in {1..5}; do
  curl -i "http://${ALB_DNS}/<500_TEST_ENDPOINT>"
  echo
done
~~~

500 테스트 endpoint가 없다면 Alarm 상태를 수동으로 변경하여 알림 흐름만 검증한다.

~~~bash
aws cloudwatch set-alarm-state \
  --alarm-name "olivesafety-day2-ops-dev-alb-target-5xx" \
  --state-value ALARM \
  --state-reason "Manual test for ALB target 5xx alarm notification." \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE"
~~~

원복:

~~~bash
aws cloudwatch set-alarm-state \
  --alarm-name "olivesafety-day2-ops-dev-alb-target-5xx" \
  --state-value OK \
  --state-reason "Manual recovery test for ALB target 5xx alarm notification." \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE"
~~~

## Lambda 로그 확인

Teams 알림이 오지 않거나 메시지 전송이 실패한 경우 Lambda 로그를 확인한다.

~~~bash
cd terraform/envs/dev
TEAMS_LAMBDA_NAME=$(terraform output -raw teams_alert_lambda_name)
cd ../../..

aws logs tail "/aws/lambda/${TEAMS_LAMBDA_NAME}" \
  --since 30m \
  --region ap-northeast-2 \
  --profile yerim-admin
~~~

실시간 확인:

~~~bash
aws logs tail "/aws/lambda/${TEAMS_LAMBDA_NAME}" \
  --since 30m \
  --follow \
  --region ap-northeast-2 \
  --profile yerim-admin
~~~

## Teams Workflow 실패 시 확인

Teams Workflows 실행 기록에서 실패한 경우, 실패한 Action 이름과 Error message를 확인한다.

예시 오류:

~~~text
Post_card_in_a_chat_or_channel failed
Call made for a thread which is not a ChatThread
~~~

이 오류는 Workflow의 게시 대상 설정이 잘못되었을 때 발생할 수 있다.

확인할 항목:

~~~text
Post as: Flow bot
Post in: Channel
Team: 알림을 받을 Team 선택
Channel: 알림을 받을 Channel 선택
~~~

개인 채팅 또는 그룹 채팅보다 운영 알림은 Teams 채널로 먼저 구성하는 것을 권장한다.

Webhook을 재생성한 경우 Lambda 코드는 수정하지 않고 Secrets Manager의 URL만 업데이트하면 된다.

## 최종 상태 확인

Alarm 상태 확인:

~~~bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "olivesafety-day2-ops-dev" \
  --region ap-northeast-2 \
  --profile yerim-admin \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Metric:MetricName}' \
  --output table
~~~

Ingress health check path 확인:

~~~bash
kubectl get ingress olivesafety-api -n olivesafety \
  -o jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/healthcheck-path}'; echo
~~~

Target 상태 확인:

~~~bash
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason}' \
  --output table
~~~

최종적으로 다음 상태여야 한다.

~~~text
Ingress health check path: /actuator/health
ALB Target state: healthy
CloudWatch Alarm state: OK 또는 INSUFFICIENT_DATA
Teams 알림 전송: 성공
~~~

## 현재 구성 요약

현재 dev 환경에서는 다음 구성이 완료되어 있다.

~~~text
Teams Webhook URL을 AWS Secrets Manager에 저장
SNS Topic 생성
Lambda Teams Forwarder 구성
CloudWatch Alarm 생성
Lambda Error Alarm 수동 테스트 완료
ALB Target Unhealthy 실제 유발 테스트 완료
Teams 알림 수신 확인
ALB health check 원복 및 Target healthy 복구 확인
~~~

이를 통해 AWS 리소스의 장애성 조건을 CloudWatch Alarm으로 감지하고, SNS와 Lambda를 통해 Microsoft Teams로 알림을 전송하는 운영 자동화 흐름을 구성했다.

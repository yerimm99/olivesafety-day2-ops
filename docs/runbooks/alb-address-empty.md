# Runbook: ALB Ingress ADDRESS Empty

## 1. 상황

Ingress 리소스는 생성되었지만 `ADDRESS` 값이 비어 있다.

```bash
kubectl get ingress -n olivesafety
```

예시:

```text
NAME              CLASS   HOSTS   ADDRESS   PORTS   AGE
olivesafety-api   alb     *                 80      5m
```

## 2. 영향도

외부에서 애플리케이션에 접근할 수 없다.

ALB가 생성되지 않았거나, Ingress와 ALB Controller 간 처리가 정상적으로 이루어지지 않은 상태이다.

## 3. 주요 원인

1. AWS Load Balancer Controller가 설치되지 않음
2. AWS Load Balancer Controller Pod가 Running 상태가 아님
3. Controller ServiceAccount에 IRSA Role이 연결되지 않음
4. ALB Controller IAM Policy 권한 부족
5. VPC/Subnet 태그 누락
6. IngressClass 또는 annotation 설정 오류

## 4. 확인 절차

Ingress 확인:

```bash
kubectl get ingress -n olivesafety -o wide
```

Ingress 이벤트 확인:

```bash
kubectl describe ingress olivesafety-api -n olivesafety | sed -n '/Events/,$p'
```

ALB Controller 설치 여부 확인:

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```

Controller Pod 상태 확인:

```bash
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

Controller 로그 확인:

```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=100
```

ServiceAccount annotation 확인:

```bash
kubectl get sa aws-load-balancer-controller -n kube-system -o yaml | grep -A5 annotations
```

## 5. 복구 절차

ALB Controller IAM Role ARN 확인:

```bash
ALB_ROLE_ARN=$(aws iam get-role \
  --role-name olivesafety-day2-ops-dev-aws-load-balancer-controller-role \
  --profile yerim-admin \
  --query 'Role.Arn' \
  --output text)

echo $ALB_ROLE_ARN
```

EKS Cluster VPC ID 확인:

```bash
VPC_ID=$(aws eks describe-cluster \
  --name olivesafety-day2-ops-dev-eks \
  --region ap-northeast-2 \
  --profile yerim-admin \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)

echo $VPC_ID
```

AWS Load Balancer Controller 설치:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=olivesafety-day2-ops-dev-eks \
  --set region=ap-northeast-2 \
  --set vpcId=$VPC_ID \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$ALB_ROLE_ARN"
```

Controller 확인:

```bash
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

Ingress 재적용:

```bash
kubectl apply -k k8s/overlays/dev
```

## 6. 정상 확인

```bash
kubectl get ingress -n olivesafety -w
```

정상 예시:

```text
NAME              CLASS   HOSTS   ADDRESS                                                                    PORTS
olivesafety-api   alb     *       k8s-olivesaf-xxxxx.ap-northeast-2.elb.amazonaws.com                        80
```

ALB health 확인:

```bash
APP_ALB_DNS=$(kubectl get ingress olivesafety-api -n olivesafety -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl http://${APP_ALB_DNS}/actuator/health
```

## 7. 재발 방지

- `scripts/dev-up.sh`에 ALB Controller 설치 절차를 포함한다.
- ALB Controller IAM Role 이름과 Helm values를 문서화한다.
- Public subnet에 `kubernetes.io/role/elb=1` 태그가 있는지 확인한다.
- IngressClass와 annotation을 base manifest에서 일관되게 관리한다.

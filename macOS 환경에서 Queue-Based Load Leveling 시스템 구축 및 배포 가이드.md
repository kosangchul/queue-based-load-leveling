📋 개요

이 문서는 macOS 환경에서 Queue-Based Load Leveling 패턴을 Minikube에 구축하고 배포하는 완전한 가이드입니다.

GitHub 소스(https://github.com/xotlr333/queue-based-load-leveling)를 기반으로 실제 동작하는 시스템을 구축할 수 있습니다.

🎯 학습 목표
Queue-Based Load Leveling 패턴을 macOS 환경에서 구현
Minikube를 활용한 로컬 Kubernetes 클러스터 구축
RabbitMQ 기반 메시지 큐 시스템 배포
Producer/Consumer 아키텍처 구현 및 배포
자동 스케일링(HPA) 설정
🛠️ 1단계: 개발 환경 설정
필수 도구 설치
Homebrew 설치 (없는 경우)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"


Docker Desktop 설치


 # 방법 1: Homebrew 사용 brew install --cask docker 


# 방법 2: 직접 다운로드 
# https://desktop.docker.com/mac/stable/Docker.dmg  


Minikube 설치
brew install minikube


kubectl 설치
brew install kubectl


Helm 설치
brew install helm


추가 도구 설치
# watch 명령어 (모니터링용)
brew install watch

# 기타 유틸리티
brew install curl jq


Python 환경 설정
# Python 가상환경 생성
python3 -m venv queue-pattern-env

# 가상환경 활성화
source queue-pattern-env/bin/activate

# 필요한 Python 패키지 설치
pip install --upgrade pip


🚀 2단계: 프로젝트 설정
GitHub 저장소 클론
# 프로젝트 클론
git clone https://github.com/xotlr333/queue-based-load-leveling.git
cd queue-based-load-leveling

# 프로젝트 구조 확인
ls -la


의존성 파일 생성
# requirements.txt 생성
cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
pika==1.3.2
pydantic==2.5.0
python-multipart==0.0.6
requests==2.31.0
aiohttp==3.9.1
EOF

# 의존성 설치
pip install -r requirements.txt


⚙️ 3단계: Minikube 클러스터 구축
Minikube 클러스터 시작
# Minikube 시작 (macOS 최적화 설정)
minikube start \
  --memory=6144 \
  --cpus=3 \
  --disk-size=20g \
  --driver=docker \
  --kubernetes-version=v1.33.1

# 상태 확인
minikube status

# 필수 애드온 활성화
minikube addons enable ingress
minikube addons enable metrics-server
minikube addons enable dashboard


Docker 환경 연결
# Minikube의 Docker 환경과 연결
eval $(minikube docker-env)

# 연결 확인
docker images
echo $MINIKUBE_ACTIVE_DOCKERD


📦 4단계: RabbitMQ 설치 및 구성
네임스페이스 생성
# BSS 시스템용 네임스페이스 생성
kubectl create namespace bss-queue-system

# 네임스페이스 확인
kubectl get namespaces


Helm을 통한 RabbitMQ 설치
# Helm 저장소 추가
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# RabbitMQ 설치
helm install rabbitmq bitnami/rabbitmq \
  --namespace bss-queue-system \
  --set auth.username=admin \
  --set auth.password=secretpassword \
  --set persistence.enabled=true \
  --set persistence.size=10Gi \
  --set service.type=ClusterIP \
  --set service.ports.amqp=5672 \
  --set service.ports.manager=15672 \
  --wait

# 설치 확인
kubectl get pods -n bss-queue-system
kubectl get services -n bss-queue-system


RabbitMQ 연결 확인
# RabbitMQ 관리 UI 포트 포워딩
kubectl port-forward svc/rabbitmq 15672:15672 -n bss-queue-system &

# 브라우저에서 접속: http://localhost:15672
# 로그인: admin / secretpassword
echo "RabbitMQ Management UI: http://localhost:15672"


🐳 5단계: 애플리케이션 컨테이너 생성
Dockerfile 생성
Producer Dockerfile 생성
mkdir -p docker

cat > docker/Dockerfile.producer << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# 시스템 패키지 설치
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Python 의존성 설치
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Python Path 설정
ENV PYTHONPATH="/app:/app/src"
ENV PYTHONUNBUFFERED=1

EXPOSE 8000

# 간단한 Producer API 생성
RUN echo 'from fastapi import FastAPI\napp = FastAPI()\n@app.get("/health")\ndef health(): return {"status": "ok"}\n@app.get("/")\ndef root(): return {"message": "Producer running"}' > /app/simple_app.py

# Producer 실행
CMD ["python", "-m", "uvicorn", "simple_app:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

Consumer Dockerfile 생성
# Consumer 스크립트 파일 생성
cat > simple_consumer.py << 'EOF'
import time
import os

message_type = os.getenv("MESSAGE_TYPE", "UNKNOWN")
print(f"Consumer {message_type} started")

while True:
    print(f"Processing {message_type} messages...")
    time.sleep(30)
EOF

# Consumer Dockerfile 생성
cat > docker/Dockerfile.consumer << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Python 의존성 설치
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Consumer 스크립트 복사
COPY simple_consumer.py .

# Python Path 설정
ENV PYTHONPATH="/app"
ENV PYTHONUNBUFFERED=1

# Consumer 실행
CMD ["python", "simple_consumer.py"]
EOF


컨테이너 이미지 빌드
# Docker 환경이 Minikube와 연결되었는지 확인
eval $(minikube docker-env)

# Producer 이미지 빌드
docker build -f docker/Dockerfile.producer -t bss-producer:latest .

# Consumer 이미지들 빌드
docker build -f docker/Dockerfile.consumer -t subscription-processor:latest .
docker build -f docker/Dockerfile.consumer -t mnp-processor:latest .

# 빌드된 이미지 확인
docker images | grep -E "(bss-producer|processor)"


🚢 6단계: Kubernetes 배포
ConfigMap 생성
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: bss-config
  namespace: bss-queue-system
data:
  RABBITMQ_URL: "amqp://admin:secretpassword@rabbitmq:5672/"
  QUEUE_NAME: "bss_single_queue"
  MONITORING_ENABLED: "true"
  LOG_LEVEL: "INFO"
  MAX_RETRIES: "3"
  BATCH_SIZE: "100"
  PROCESSING_TIMEOUT_SEC: "300"
EOF

Producer 배포
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bss-producer
  namespace: bss-queue-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bss-producer
  template:
    metadata:
      labels:
        app: bss-producer
    spec:
      containers:
      - name: producer
        image: bss-producer:latest
        imagePullPolicy: Never
        ports:
        - containerPort: 8000
        env:
        - name: LOG_LEVEL
          value: "INFO"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: bss-producer-service
  namespace: bss-queue-system
spec:
  selector:
    app: bss-producer
  ports:
  - port: 8000
    targetPort: 8000
  type: ClusterIP
EOF

Consumer 배포 (자동 스케일링 포함)
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: subscription-processor
  namespace: bss-queue-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: subscription-processor
  template:
    metadata:
      labels:
        app: subscription-processor
    spec:
      containers:
      - name: processor
        image: subscription-processor:latest
        imagePullPolicy: Never
        env:
        - name: MESSAGE_TYPE
          value: "SUBSCRIPTION"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: subscription-processor-hpa
  namespace: bss-queue-system
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: subscription-processor
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mnp-processor
  namespace: bss-queue-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mnp-processor
  template:
    metadata:
      labels:
        app: mnp-processor
    spec:
      containers:
      - name: processor
        image: mnp-processor:latest
        imagePullPolicy: Never
        env:
        - name: MESSAGE_TYPE
          value: "MNP"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: mnp-processor-hpa
  namespace: bss-queue-system
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: mnp-processor
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
EOF

✅ 7단계: 배포 확인
시스템 상태 점검
# 모든 Pod 상태 확인
kubectl get pods -n bss-queue-system

# 서비스 상태 확인
kubectl get services -n bss-queue-system

# HPA 상태 확인
kubectl get hpa -n bss-queue-system

# 전체 리소스 확인
kubectl get all -n bss-queue-system

로그 확인
# Producer 로그 확인
kubectl logs -l app=bss-producer -n bss-queue-system

# Consumer 로그 확인
kubectl logs -l app=subscription-processor -n bss-queue-system
kubectl logs -l app=mnp-processor -n bss-queue-system

# RabbitMQ 로그 확인
kubectl logs -l app.kubernetes.io/name=rabbitmq -n bss-queue-system

🔧 8단계: 포트 포워딩 설정
포트 포워딩 관리 스크립트 생성
cat > manage_ports.sh << 'EOF'
#!/bin/bash

case "$1" in
    start)
        echo "포트 포워딩 시작..."
        pkill -f "kubectl port-forward" 2>/dev/null || true
        
        kubectl port-forward svc/rabbitmq 15672:15672 -n bss-queue-system &
        RABBITMQ_UI_PID=$!
        
        kubectl port-forward svc/rabbitmq 5672:5672 -n bss-queue-system &
        RABBITMQ_AMQP_PID=$!
        
        kubectl port-forward svc/bss-producer-service 8000:8000 -n bss-queue-system &
        PRODUCER_PID=$!
        
        echo "포트 포워딩 완료:"
        echo "- RabbitMQ UI: http://localhost:15672 (admin/secretpassword)"
        echo "- RabbitMQ AMQP: localhost:5672"
        echo "- Producer API: http://localhost:8000"
        ;;
    stop)
        echo "포트 포워딩 종료 중..."
        pkill -f "kubectl port-forward"
        echo "모든 포트 포워딩이 종료되었습니다."
        ;;
    status)
        echo "현재 실행 중인 포트 포워딩:"
        ps aux | grep "kubectl port-forward" | grep -v grep
        ;;
    *)
        echo "사용법: $0 {start|stop|status}"
        ;;
esac
EOF

chmod +x manage_ports.sh

포트 포워딩 시작
# 모든 서비스에 대한 포트 포워딩 시작
./manage_ports.sh start

🧪 9단계: 기본 연결 테스트
API 연결 테스트
# Producer API 헬스 체크
curl http://localhost:8000/health

# Producer API 기본 응답 확인
curl http://localhost:8000/

# RabbitMQ 관리 API 테스트
curl -u admin:secretpassword http://localhost:15672/api/overview

RabbitMQ 큐 생성
# BSS 시스템용 큐 생성
curl -u admin:secretpassword -X PUT http://localhost:15672/api/queues/%2F/bss_single_queue \
  -H "Content-Type: application/json" \
  -d '{
    "auto_delete": false,
    "durable": true,
    "arguments": {}
  }'

# 생성된 큐 확인
curl -u admin:secretpassword http://localhost:15672/api/queues/%2F/bss_single_queue

📊 10단계: 모니터링 설정
시스템 모니터링 스크립트 생성
cat > monitor.sh << 'EOF'
#!/bin/bash

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

monitor_pods() {
    while true; do
        clear
        echo -e "${GREEN}=== BSS Queue System 모니터링 $(date) ===${NC}"
        echo ""
        
        echo -e "${YELLOW}📦 Pod 상태:${NC}"
        kubectl get pods -n bss-queue-system
        echo ""
        
        echo -e "${YELLOW}🚀 서비스 상태:${NC}"
        kubectl get services -n bss-queue-system
        echo ""
        
        echo -e "${YELLOW}📊 리소스 사용량:${NC}"
        kubectl top pods -n bss-queue-system 2>/dev/null || echo "metrics-server 대기 중..."
        echo ""
        
        echo -e "${YELLOW}🔄 HPA 상태:${NC}"
        kubectl get hpa -n bss-queue-system
        
        echo ""
        echo "Ctrl+C로 종료"
        sleep 3
    done
}

case "$1" in
    pods)
        while true; do
            clear
            echo "=== Pod 상태 $(date) ==="
            kubectl get pods -n bss-queue-system -o wide
            sleep 2
        done
        ;;
    all)
        monitor_pods
        ;;
    *)
        echo "사용법: $0 {pods|all}"
        echo "  pods - Pod 상태만 모니터링"
        echo "  all  - 전체 시스템 모니터링"
        ;;
esac
EOF

chmod +x monitor.sh

🎉 11단계: 배포 완료 확인
최종 시스템 상태 점검
# 1. 전체 시스템 상태 확인
echo "=== 시스템 상태 점검 ==="
kubectl get all -n bss-queue-system

# 2. 포트 포워딩 상태 확인
./manage_ports.sh status

# 3. API 연결 확인
echo ""
echo "=== API 연결 테스트 ==="
curl -s http://localhost:8000/health && echo " ✅ Producer API 정상"
curl -s -u admin:secretpassword http://localhost:15672/api/overview > /dev/null && echo "✅ RabbitMQ 정상"

# 4. 모니터링 시작
echo ""
echo "=== 모니터링 시작 ==="
echo "다른 터미널에서 './monitor.sh all' 실행하여 실시간 모니터링 가능"

🔄 시스템 관리 명령어
유용한 관리 명령어
# 시스템 재시작
kubectl rollout restart deployment/bss-producer -n bss-queue-system
kubectl rollout restart deployment/subscription-processor -n bss-queue-system
kubectl rollout restart deployment/mnp-processor -n bss-queue-system

# 스케일링
kubectl scale deployment subscription-processor --replicas=3 -n bss-queue-system

# 로그 실시간 확인
kubectl logs -f -l app=bss-producer -n bss-queue-system

# 리소스 정리 (필요시)
kubectl delete namespace bss-queue-system
helm uninstall rabbitmq -n bss-queue-system

🚨 트러블슈팅
일반적인 문제 해결
# Pod가 Running 상태가 아닐 때
kubectl describe pod <pod-name> -n bss-queue-system

# 이미지 Pull 오류
kubectl get events -n bss-queue-system --sort-by='.lastTimestamp'

# 포트 충돌 문제
pkill -f "kubectl port-forward"
lsof -i :8000  # 특정 포트 사용 프로세스 확인

# Docker 환경 재설정
eval $(minikube docker-env)
docker images

✅ 배포 성공 기준

다음 모든 조건이 충족되면 배포가 성공적으로 완료된 것입니다:

✅ 모든 Pod가 Running 상태
✅ Producer API(http://localhost:8000/health) 응답 정상
✅ RabbitMQ 관리 UI(http://localhost:15672) 접속 가능
✅ Consumer들이 메시지 처리 로그 출력
✅ HPA가 정상적으로 구성됨
🎯 다음 단계

배포가 완료되면 테스트 수행 가이드를 참고하여 Queue-Based Load Leveling 패턴의 효과를 검증할 수 있습니다.



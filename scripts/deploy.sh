# ���� ���: scripts/deploy.sh
# ��ü �ý��� ���� ��ũ��Ʈ

#!/bin/bash

set -e

echo "=== BSS Queue-Based Load Leveling ���� ���� ==="

# 1. ���ӽ����̽� �� �⺻ ����
echo "1. ���ӽ����̽� �� ���� ���� ��..."
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap/

# 2. RabbitMQ ��ġ
echo "2. RabbitMQ ��ġ ��..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm install rabbitmq bitnami/rabbitmq \
  --namespace bss-queue-system \
  --values k8s/rabbitmq/values.yaml \
  --wait

# 3. Docker �̹��� ����
echo "3. Docker �̹��� ���� ��..."
eval $(minikube docker-env)

docker build -f docker/Dockerfile.producer -t bss-producer:latest .
docker build -f docker/Dockerfile.consumer -t bss-consumer:latest .

# 4. Producer ���� ����
echo "4. Producer ���� ���� ��..."
kubectl apply -f k8s/producer/

# 5. Consumer ���� ����
echo "5. Consumer ���� ���� ��..."
kubectl apply -f k8s/consumer/

# 6. ���� ���� Ȯ��
echo "6. ���� ���� Ȯ�� ��..."
kubectl get pods -n bss-queue-system
kubectl get services -n bss-queue-system

echo "7. ���� �Ϸ�!"
echo "   - API ����: http://$(minikube ip):30080"
echo "   - RabbitMQ UI: kubectl port-forward svc/rabbitmq 15672:15672 -n bss-queue-system"
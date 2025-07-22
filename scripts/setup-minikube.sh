# ���� ���: scripts/setup-minikube.sh
# Minikube ȯ�� ���� ��ũ��Ʈ

#!/bin/bash

set -e

echo "=== BSS Queue-Based Load Leveling ���� - Minikube ȯ�� ���� ==="

# Minikube ����
echo "1. Minikube ���� ��..."
minikube start --memory=8192 --cpus=4 --disk-size=20g --driver=docker

# �ֵ�� Ȱ��ȭ
echo "2. �ʼ� �ֵ�� Ȱ��ȭ ��..."
minikube addons enable ingress
minikube addons enable metrics-server

# Docker ȯ�� ����
echo "3. Docker ȯ�� ���� ��..."
eval $(minikube docker-env)

# Helm ��ġ Ȯ��
echo "4. Helm ��ġ Ȯ�� ��..."
if ! command -v helm &> /dev/null; then
    echo "Helm�� ��ġ���� �ʾҽ��ϴ�. ��ġ�� �����մϴ�..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "5. Minikube ���� �Ϸ�!"
echo "   - IP: $(minikube ip)"
echo "   - Dashboard: minikube dashboard"
echo "   - ����: $(minikube status)"
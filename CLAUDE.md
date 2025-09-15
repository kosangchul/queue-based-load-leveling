# CLAUDE.md

이 파일은 이 저장소에서 작업할 때 Claude Code (claude.ai/code)에게 지침을 제공합니다.

## 프로젝트 개요

Python, FastAPI, RabbitMQ, Kubernetes를 사용하여 Queue-Based Load Leveling 패턴을 구현한 BSS(Business Support System)입니다. 단일 큐를 통해 4가지 메시지 타입(SUBSCRIPTION, MNP, CHANGE, TERMINATION)을 처리하며 타입별 전용 Consumer가 메시지를 필터링합니다.

## 아키텍처

### 핵심 컴포넌트
- **Producer**: FastAPI 기반 API Gateway, Message Router, Producer
- **Queue**: 모든 메시지 타입을 처리하는 단일 RabbitMQ 큐
- **Consumer**: 메시지 타입별로 필터링하는 4개의 전용 처리기
- **Monitoring**: Prometheus 연동 선택적 메트릭 수집

### 주요 디렉토리
- `src/common/`: 공통 설정 및 메시지 모델
- `src/producer/`: API Gateway, 메시지 라우터, 프로듀서
- `src/consumer/`: 4개 메시지 타입 처리기 (가입, 번호이동, 명의변경, 해지)
- `src/monitoring/`: 메트릭 수집 및 모니터링 스위치
- `k8s/`: Kubernetes 배포 매니페스트
- `docker/`: Dockerfile 구성
- `scripts/`: 배포 및 테스트 자동화
- `tests/`: 단위 테스트 및 통합 테스트

## 개발 명령어

### 환경 설정
```bash
# Minikube 환경 설정
./scripts/setup-minikube.sh

# 전체 시스템 배포
./scripts/deploy.sh

# 배포 정리
./scripts/cleanup.sh
```

### 테스트
```bash
# 커버리지 포함 전체 테스트 실행
pytest tests/ --cov=src --cov-report=html

# 특정 테스트 파일 실행
pytest tests/test_message_models.py -v

# 통합 테스트 실행
pytest tests/test_integration.py -v
```

### 패턴 검증
```bash
# 기본 부하 테스트 실행
python scripts/test-pattern.py --test-type basic

# 패턴 검증 테스트 실행
python scripts/test-pattern.py --test-type validation

# 종합 테스트 실행
python scripts/test-pattern.py --test-type all

# 빠른 실험 스크립트
./scripts/run-experiments.sh
```

### 코드 품질
```bash
# 코드 포맷팅
black src/ tests/

# import 정렬
isort src/ tests/

# 코드 린팅
flake8 src/ tests/
```

### Docker 개발
```bash
# 로컬 이미지 빌드
eval $(minikube docker-env)
docker build -f docker/Dockerfile.producer -t bss-producer:latest .
docker build -f docker/Dockerfile.consumer -t bss-consumer:latest .

# 로컬 테스트용 Docker Compose 실행
cd docker && docker-compose up -d
```

## 설정

### 환경 변수
주요 설정은 `src/common/config.py`에서 관리됩니다:
- `RABBITMQ_URL`: RabbitMQ 연결 문자열
- `QUEUE_NAME`: 단일 큐 이름 (기본값: bss_single_queue)
- `MONITORING_ENABLED`: 모니터링 토글 (true/false)
- `LOG_LEVEL`: 로깅 레벨 (INFO, DEBUG, ERROR)
- `MAX_RETRIES`: 메시지 재시도 횟수
- `PROCESSING_TIMEOUT_SEC`: Consumer 처리 타임아웃

### API 엔드포인트
- Producer API는 8000번 포트에서 실행 (K8s에서는 30080)
- 헬스 체크: `/health`
- 메시지 전송: `POST /api/message`, `POST /api/messages/batch`
- 큐 상태: `GET /api/queue/status`
- 통계: `GET /api/stats`
- 모니터링 토글: `POST /api/monitoring/toggle`

## 메시지 처리

### 메시지 타입
모든 메시지는 `src/common/message_models.py`에 정의된 BSS메시지 모델을 따릅니다:
- SUBSCRIPTION: 가입처리서비스
- MNP: 번호이동처리서비스  
- CHANGE: 명의변경처리서비스
- TERMINATION: 해지처리서비스

### Consumer 아키텍처
각 Consumer는 `base_processor.py`를 확장하고 타입별 필터링을 구현합니다:
- 단일 큐 → 다중 전용 Consumer
- 각 Consumer에서 타입별 메시지 필터링
- 자동 확인 및 오류 처리

## 모니터링

시스템은 `src/monitoring/monitoring_switch.py`를 통한 선택적 모니터링을 포함합니다:
- Prometheus 메트릭 수집
- 성능 오버헤드 최소화
- 런타임 토글 기능
- 큐 길이, 처리 시간, 처리량 메트릭

## 테스트 전략

- **단위 테스트**: 개별 컴포넌트 테스트
- **통합 테스트**: 전체 시스템 워크플로우 테스트  
- **패턴 검증**: 부하 평활화 효과 측정
- **부하 테스트**: 성능 및 확장성 테스트

개발 테스트는 `pytest tests/`를, 종합 패턴 검증은 `scripts/test-pattern.py`를 사용하세요.
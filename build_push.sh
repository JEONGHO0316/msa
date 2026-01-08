#!/bin/bash

# ==========================================
# 설정 변수 (이 부분만 수정해서 쓰세요)
# ==========================================
REGION="ap-northeast-2"
VERSION="4.0.1"  # 아까 확인한 JAR 파일 버전
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 서비스 목록 ("폴더명:포트번호")
# 주의: 폴더명은 spring-petclinic-aaa 형식이지만, 
# ECR 리포지토리 이름은 aaa 로 만들기 위해 스크립트가 자동으로 자릅니다.
SERVICES=(
    "spring-petclinic-config-server:8888"
    "spring-petclinic-discovery-server:8761"
    "spring-petclinic-customers-service:8081"
    "spring-petclinic-vets-service:8082"
    "spring-petclinic-visits-service:8083"
    "spring-petclinic-api-gateway:8080"
    "spring-petclinic-admin-server:9090"
)

# ==========================================
# 1. ECR 로그인
# ==========================================
echo "🔑 ECR 로그인 중..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

echo "--------------------------------------------------"

# ==========================================
# 2. 반복문 실행 (빌드 -> 리포지토리 생성 -> 푸시)
# ==========================================
for entry in "${SERVICES[@]}"; do
    # 문자열 파싱 (폴더명과 포트 분리)
    FOLDER_NAME=${entry%%:*}
    PORT=${entry##*:}
    
    # ECR 리포지토리 이름은 'spring-petclinic-'을 뺀 짧은 이름으로 사용 (예: config-server)
    REPO_NAME=${FOLDER_NAME#spring-petclinic-}

    FULL_IMAGE_NAME="$AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest"
    ARTIFACT_PATH="$FOLDER_NAME/target/$FOLDER_NAME-$VERSION"

    echo "🚀 [Start] $REPO_NAME (Port: $PORT) 처리 시작..."

    # 2-1. ECR 리포지토리 생성 (이미 있으면 통과)
    aws ecr describe-repositories --repository-names $REPO_NAME --region $REGION > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "   📦 ECR 리포지토리($REPO_NAME)가 없어서 생성합니다..."
        aws ecr create-repository --repository-name $REPO_NAME --region $REGION > /dev/null
    else
        echo "   ✅ ECR 리포지토리($REPO_NAME)가 이미 존재합니다."
    fi

    # 2-2. Docker Build
    echo "   🐳 Docker Build 중..."
    docker build -t $REPO_NAME:latest \
        -f docker/Dockerfile \
        --build-arg ARTIFACT_NAME=$ARTIFACT_PATH \
        --build-arg EXPOSED_PORT=$PORT \
        . > /dev/null
    
    if [ $? -ne 0 ]; then
        echo "   ❌ 빌드 실패! ($REPO_NAME)"
        exit 1
    fi

    # 2-3. Tag & Push
    echo "   🏷️  Tag & Push 중..."
    docker tag $REPO_NAME:latest $FULL_IMAGE_NAME
    docker push $FULL_IMAGE_NAME > /dev/null

    echo "   ✨ 완료! ($FULL_IMAGE_NAME)"
    echo "--------------------------------------------------"
done

echo "🎉 모든 서비스의 빌드 및 푸시가 완료되었습니다!"

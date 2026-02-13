#!/bin/bash
set -e

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 项目根目录 (假设 olares 目录在项目根目录下)
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 检查是否提供了版本参数
if [ -z "$1" ]; then
    echo "Error: Image version is required."
    echo "Usage: $0 <version>"
    echo "Example: $0 0.1.0"
    exit 1
fi

IMAGE_NAME="yt-navigator"
TAG="$1"

echo "Using Dockerfile at: $PROJECT_ROOT/Dockerfile"
echo "Build context: $PROJECT_ROOT"

echo "Building Docker image: $IMAGE_NAME:$TAG..."
# 使用 BuildKit 启用缓存挂载特性
DOCKER_BUILDKIT=1 docker build \
  -t "$IMAGE_NAME:$TAG" \
  -f "$PROJECT_ROOT/Dockerfile" \
  "$PROJECT_ROOT"

echo "Build complete successfully!"
echo "Image: $IMAGE_NAME:$TAG"

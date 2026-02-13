#!/bin/bash
set -e

# 进入脚本所在目录 (olares)
cd "$(dirname "${BASH_SOURCE[0]}")"

# 检查上一级目录是否存在 .env 文件
if [ ! -f "../.env" ]; then
    echo "Warning: '../.env' file not found."
    if [ -f "../.env.example" ]; then
        echo "Creating '../.env' from '../.env.example'..."
        cp "../.env.example" "../.env"
        echo "Created .env file. Please check configuration if needed."
    else
        echo "Error: '../.env.example' also missing. Cannot create .env file."
        exit 1
    fi
else
    echo "Found existing .env file."
fi

# 启动 Docker Compose
echo "Starting services with Docker Compose..."
docker compose up -d

echo "Services started."
echo "You can view logs with: docker compose logs -f"

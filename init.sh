#!/bin/bash

# share_stacks 目录结构初始化脚本
# 用于创建部署所需的目录结构

set -e

echo "========================================="
echo "share_stacks 目录结构初始化"
echo "========================================="
echo ""

# 检查是否在项目根目录
if [ ! -f "docker-compose.yml" ]; then
    echo "错误: 请在 share_stacks 项目根目录下运行此脚本"
    exit 1
fi

echo "创建目录结构..."

# 创建主要目录
mkdir -p litellm
mkdir -p mcpo
mkdir -p postgres-init
mkdir -p newapi-data
mkdir -p logs/newapi
mkdir -p logs/litellm

echo "✓ litellm/"
echo "✓ mcpo/"
echo "✓ postgres-init/"
echo "✓ newapi-data/"
echo "✓ logs/newapi/"
echo "✓ logs/litellm/"
echo ""

# 检查 .env 文件
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        echo "复制 .env.example 到 .env"
        cp .env.example .env
        echo "⚠ 请编辑 .env 文件，修改所有密码和密钥！"
        echo ""
    else
        echo "警告: .env.example 文件不存在"
    fi
else
    echo "✓ .env 文件已存在"
fi

echo ""
echo "========================================="
echo "初始化完成！"
echo "========================================="
echo ""
echo "下一步操作:"
echo "1. 编辑 .env 文件，修改所有密码和密钥"
echo "2. 运行: docker compose up -d"
echo "3. 运行验证脚本: bash verify.sh"

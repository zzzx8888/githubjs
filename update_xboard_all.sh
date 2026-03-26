#!/bin/bash

# 固定镜像（你要更新的目标镜像）
IMAGE_NAME="ghcr.io/cedar2025/xboard-node:latest"

echo "============================================="
echo "  Xboard Node 全自动批量更新脚本"
echo "  自动扫描 → 自动备份配置 → 自动重建"
echo "============================================="

# 1. 查找所有使用该镜像的容器 ID
CONTAINERS=$(docker ps -a --filter "ancestor=$IMAGE_NAME" -q)

if [ -z "$CONTAINERS" ]; then
    echo "❌ 未找到任何 $IMAGE_NAME 容器，退出"
    exit 1
fi

echo "✅ 找到容器数量：$(echo "$CONTAINERS" | wc -l)"
echo ""

# 保存所有容器配置
declare -a CONTAINER_CONFIGS=()

# 2. 遍历每个容器，提取环境变量
for cid in $CONTAINERS; do
    echo "📦 处理容器：$cid"

    # 读取环境变量
    apiHost=$(docker inspect "$cid" | grep -o '"apiHost=[^"]*"' | sed 's/"//g' | head -1)
    apiKey=$(docker inspect "$cid" | grep -o '"apiKey=[^"]*"' | sed 's/"//g' | head -1)
    nodeID=$(docker inspect "$cid" | grep -o '"nodeID=[^"]*"' | sed 's/"//g' | head -1)

    echo "   ├─ $apiHost"
    echo "   ├─ $apiKey"
    echo "   └─ $nodeID"
    echo ""

    CONTAINER_CONFIGS+=("$apiHost|$apiKey|$nodeID")
done

# 3. 停止并删除所有旧容器
echo "🗑 停止并删除旧容器..."
for cid in $CONTAINERS; do
    docker stop "$cid" > /dev/null 2>&1
    docker rm "$cid" > /dev/null 2>&1
done

# 4. 拉取最新镜像
echo "🔄 拉取最新镜像：$IMAGE_NAME"
docker pull "$IMAGE_NAME"

# 5. 按原配置重建所有容器
echo "🚀 开始重建容器..."
for config in "${CONTAINER_CONFIGS[@]}"; do
    IFS='|' read -r h k i <<< "$config"

    docker run -d \
      --restart=always \
      --network=host \
      -e "$h" \
      -e "$k" \
      -e "$i" \
      "$IMAGE_NAME"

    echo "✅ 重建完成：$h"
done

echo ""
echo "============================================="
echo "🎉 所有节点更新完成！已全部使用最新镜像"
echo "============================================="

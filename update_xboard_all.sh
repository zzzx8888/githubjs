#!/bin/bash

IMAGE_NAME="ghcr.io/cedar2025/xboard-node:latest"

echo "============================================="
echo "  Xboard Node 全自动批量更新脚本"
echo "============================================="

CONTAINERS=$(docker ps -a --filter "ancestor=$IMAGE_NAME" -q)

if [ -z "$CONTAINERS" ]; then
    echo "❌ 未找到任何 $IMAGE_NAME 容器，退出"
    exit 1
fi

echo "✅ 找到容器数量：$(echo "$CONTAINERS" | wc -l)"
echo ""

declare -a CONTAINER_CONFIGS=()

for cid in $CONTAINERS; do
    echo "📦 处理容器：$cid"

    apiHost=$(docker inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $cid | grep ^apiHost=)
    apiKey=$(docker inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $cid | grep ^apiKey=)
    nodeID=$(docker inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $cid | grep ^nodeID=)

    echo "   ├─ $apiHost"
    echo "   ├─ $apiKey"
    echo "   └─ $nodeID"
    echo ""

    CONTAINER_CONFIGS+=("$apiHost|$apiKey|$nodeID")
done

echo "🗑 停止并删除旧容器..."
for cid in $CONTAINERS; do
    docker stop "$cid" > /dev/null 2>&1
    docker rm "$cid" > /dev/null 2>&1
done

echo "🔄 拉取最新镜像：$IMAGE_NAME"
docker pull "$IMAGE_NAME"

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

    echo "✅ 重建完成"
done

echo ""
echo "============================================="
echo "🎉 所有节点更新完成！"
echo "============================================="

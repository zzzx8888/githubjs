#!/bin/bash
IMAGE_NAME="ghcr.io/cedar2025/xboard-node:latest"

echo "============================================="
echo "  Xboard Node 全自动批量更新脚本"
echo "  功能：清理无效容器 + 仅更新运行中节点"
echo "============================================="

# 第一步：清理所有 非运行状态 的 xboard 容器（你要的功能）
echo "🧹 清理已停止的旧容器..."
docker ps -a --filter "ancestor=$IMAGE_NAME" --filter "status=exited" -q | xargs -r docker rm > /dev/null 2>&1

# 第二步：只获取 正在运行 的容器
CONTAINERS=$(docker ps --filter "ancestor=$IMAGE_NAME" -q)

if [ -z "$CONTAINERS" ]; then
    echo "❌ 未找到运行中的节点容器"
    exit 1
fi

echo "✅ 找到运行中节点：$(echo "$CONTAINERS" | wc -l)"
echo ""

declare -a CONTAINER_CONFIGS=()

# 读取每个运行中容器的配置
for cid in $CONTAINERS; do
    echo "📦 处理容器：$cid"

    apiHost=$(docker inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $cid | grep ^apiHost=)
    apiKey=$(docker inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $cid | grep ^apiKey=)
    nodeID=$(docker inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $cid | grep ^nodeID=)

    if [ -z "$apiHost" ] || [ -z "$apiKey" ] || [ -z "$nodeID" ]; then
        echo "⚠️  容器 $cid 无效，跳过"
        continue
    fi

    echo "   ├─ $apiHost"
    echo "   ├─ $apiKey"
    echo "   └─ $nodeID"
    CONTAINER_CONFIGS+=("$apiHost|$apiKey|$nodeID")
done

# 停止并删除旧容器
echo "🗑 停止旧容器..."
for cid in $CONTAINERS; do
    docker stop $cid > /dev/null 2>&1
    docker rm $cid > /dev/null 2>&1
done

# 更新镜像
echo "🔄 拉取最新镜像..."
docker pull $IMAGE_NAME

# 重建容器
echo "🚀 重建容器..."
for cfg in "${CONTAINER_CONFIGS[@]}"; do
    IFS='|' read h k i <<< "$cfg"
    docker run -d \
      --restart=always \
      --network=host \
      -e "$h" \
      -e "$k" \
      -e "$i" \
      $IMAGE_NAME
done

echo ""
echo "============================================="
echo "🎉 所有运行中节点更新完成！"
echo "============================================="

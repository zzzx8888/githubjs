#!/bin/bash
IMAGE_NAME="ghcr.io/cedar2025/xboard-node:latest"
echo "============================================="
echo "  Xboard Node 全自动批量更新脚本 (安全版)"
echo "  逻辑：先拉取镜像，拉取成功后再重建容器"
echo "============================================="
# 1. 尝试拉取最新镜像
echo "🔄 步骤 1: 正在拉取最新镜像..."
if ! docker pull $IMAGE_NAME; then
    echo "❌ 镜像拉取失败！检测到网络异常或仓库连接中断。"
    echo "💡 为了保障服务不受影响，脚本已停止执行。旧节点将维持现状运行。"
    exit 1
fi
echo "✅ 镜像拉取成功！"
# 2. 清理所有 非运行状态 的旧容器
echo "🧹 步骤 2: 清理已停止的旧容器..."
docker ps -a --filter "ancestor=$IMAGE_NAME" --filter "status=exited" -q | xargs -r docker rm > /dev/null 2>&1
# 3. 获取当前 正在运行 的容器
CONTAINERS=$(docker ps --filter "ancestor=$IMAGE_NAME" -q)
if [ -z "$CONTAINERS" ]; then
    echo "❌ 未找到运行中的节点容器，无需进一步更新。"
    exit 0
fi
echo "✅ 找到运行中节点：$(echo "$CONTAINERS" | wc -l)"
declare -a CONTAINER_CONFIGS=()
# 4. 提取配置（在删除前备份环境变量）
for cid in $CONTAINERS; do
    echo "📦 提取配置：$cid"
    apiHost=$(docker inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $cid | grep ^apiHost=)
    apiKey=$(docker inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $cid | grep ^apiKey=)
    nodeID=$(docker inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $cid | grep ^nodeID=)
    if [ -z "$apiHost" ] || [ -z "$apiKey" ] || [ -z "$nodeID" ]; then
        echo "⚠️  容器 $cid 环境变量不完整，跳过"
        continue
    fi
    CONTAINER_CONFIGS+=("$apiHost|$apiKey|$nodeID|$cid")
done
# 5. 停止并删除旧容器
echo "🗑 正在停止并移除旧节点..."
for cfg in "${CONTAINER_CONFIGS[@]}"; do
    IFS='|' read h k i cid <<< "$cfg"
    docker stop $cid > /dev/null 2>&1
    docker rm $cid > /dev/null 2>&1
done
# 6. 重建容器
echo "🚀 正在使用新镜像重建节点..."
for cfg in "${CONTAINER_CONFIGS[@]}"; do
    IFS='|' read h k i cid <<< "$cfg"
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
echo "🎉 所有运行中节点已成功更新并重启！"
echo "============================================="

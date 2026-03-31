#!/bin/bash
IMAGE_NAME="ghcr.io/cedar2025/xboard-node:latest"

echo "============================================="
echo "  Xboard Node 全自动批量更新脚本 (安全版)"
echo "  逻辑：先拉取镜像，拉取成功后再重建容器"
echo "============================================="

# 1. 拉取最新镜像
echo "🔄 步骤 1: 正在拉取最新镜像..."
if ! docker pull $IMAGE_NAME; then
    echo "❌ 镜像拉取失败！脚本已停止，旧节点维持运行。"
    exit 1
fi
echo "✅ 镜像拉取成功！"

# ✅ 核心修复：拉取后获取新镜像ID，再找所有用【任意镜像】跑 xboard-node 命令的容器
NEW_IMAGE_ID=$(docker inspect --format '{{.Id}}' $IMAGE_NAME | cut -c1-12)
echo "📌 新镜像ID：$NEW_IMAGE_ID"

# 2. 查找所有运行 xboard-node 命令的容器（不依赖镜像名/ID，直接看启动命令）
echo "🔍 步骤 2: 查找运行中的 xboard-node 容器..."
CONTAINERS=$(docker ps --format "{{.ID}} {{.Command}}" | grep "xboard-node" | awk '{print $1}')

if [ -z "$CONTAINERS" ]; then
    echo "❌ 未找到运行中的节点容器（通过命令匹配）。"
    echo "💡 当前所有运行容器："
    docker ps --format "  {{.ID}}  {{.Image}}  {{.Command}}  {{.Names}}"
    exit 0
fi
echo "✅ 找到运行中节点：$(echo "$CONTAINERS" | wc -l) 个"

declare -a CONTAINER_CONFIGS=()

# 3. 提取配置
for cid in $CONTAINERS; do
    echo "📦 提取配置：$cid"
    apiHost=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' $cid | grep "^apiHost=")
    apiKey=$(docker inspect  --format '{{range .Config.Env}}{{println .}}{{end}}' $cid | grep "^apiKey=")
    nodeID=$(docker inspect  --format '{{range .Config.Env}}{{println .}}{{end}}' $cid | grep "^nodeID=")

    if [ -z "$apiHost" ] || [ -z "$apiKey" ] || [ -z "$nodeID" ]; then
        echo "⚠️  容器 $cid 环境变量不完整，跳过"
        echo "   apiHost='$apiHost'"
        echo "   apiKey='$apiKey'"
        echo "   nodeID='$nodeID'"
        # 打印全部环境变量供排查
        echo "   全部ENV："
        docker inspect --format '{{range .Config.Env}}    {{println .}}{{end}}' $cid
        continue
    fi
    echo "   ✅ apiHost OK | apiKey OK | $nodeID"
    CONTAINER_CONFIGS+=("${apiHost}"$'\x1F'"${apiKey}"$'\x1F'"${nodeID}"$'\x1F'"${cid}")
done

if [ ${#CONTAINER_CONFIGS[@]} -eq 0 ]; then
    echo "❌ 所有容器配置提取失败，终止更新。"
    exit 1
fi

# 4. 停止并删除旧容器
echo "🗑  正在停止并移除旧节点..."
for cfg in "${CONTAINER_CONFIGS[@]}"; do
    IFS=$'\x1F' read h k i cid <<< "$cfg"
    docker stop $cid > /dev/null 2>&1 && docker rm $cid > /dev/null 2>&1
    echo "   已移除：$cid"
done

# 5. 重建容器
echo "🚀 正在使用新镜像重建节点..."
for cfg in "${CONTAINER_CONFIGS[@]}"; do
    IFS=$'\x1F' read h k i cid <<< "$cfg"
    NEW_CID=$(docker run -d \
        --restart=always \
        --network=host \
        -e "$h" \
        -e "$k" \
        -e "$i" \
        $IMAGE_NAME)
    if [ $? -eq 0 ]; then
        echo "   ✅ 新容器已启动：${NEW_CID:0:12}（$i）"
    else
        echo "   ❌ 启动失败：$h / $i"
    fi
done

echo ""
echo "============================================="
echo "🎉 所有节点已成功更新！"
echo "============================================="

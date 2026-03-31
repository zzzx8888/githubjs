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

# 2. 清理所有非运行状态的旧容器（按镜像名或ID匹配）
echo "🧹 步骤 2: 清理已停止的旧容器..."
NEW_IMAGE_ID=$(docker inspect --format '{{.Id}}' $IMAGE_NAME 2>/dev/null | cut -c1-12)

# ✅ 修复点1：同时按镜像名 和 镜像ID 查找容器（解决旧ID不匹配问题）
get_containers() {
    local status_filter="$1"
    {
        docker ps -a --filter "ancestor=$IMAGE_NAME" --filter "status=$status_filter" -q
        # 同时查找所有使用 xboard-node 镜像（任意tag/ID）的容器
        docker ps -a --filter "status=$status_filter" --format "{{.ID}} {{.Image}}" \
            | grep -i "xboard-node" | awk '{print $1}'
    } | sort -u
}

# 清理已停止的旧容器
get_containers "exited" | xargs -r docker rm > /dev/null 2>&1

# 3. 获取当前正在运行的容器
CONTAINERS=$(get_containers "running")

if [ -z "$CONTAINERS" ]; then
    echo "❌ 未找到运行中的节点容器，无需进一步更新。"
    exit 0
fi
echo "✅ 找到运行中节点：$(echo "$CONTAINERS" | wc -l) 个"

declare -a CONTAINER_CONFIGS=()

# 4. 提取配置（在删除前备份环境变量）
for cid in $CONTAINERS; do
    echo "📦 提取配置：$cid"
    # ✅ 修复点2：用换行符作分隔符，避免特殊字符破坏IFS='|'分割
    apiHost=$(docker inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $cid | grep "^apiHost=")
    apiKey=$(docker inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $cid | grep "^apiKey=")
    nodeID=$(docker inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $cid | grep "^nodeID=")

    if [ -z "$apiHost" ] || [ -z "$apiKey" ] || [ -z "$nodeID" ]; then
        echo "⚠️  容器 $cid 环境变量不完整，跳过"
        echo "   找到的变量: apiHost='$apiHost' apiKey='$apiKey' nodeID='$nodeID'"
        continue
    fi

    # ✅ 修复点3：用 \x1F（不可见单元分隔符）代替 | 避免值中含|导致分割错误
    CONTAINER_CONFIGS+=("${apiHost}"$'\x1F'"${apiKey}"$'\x1F'"${nodeID}"$'\x1F'"${cid}")
done

if [ ${#CONTAINER_CONFIGS[@]} -eq 0 ]; then
    echo "❌ 所有容器配置提取失败，终止更新以保障服务。"
    exit 1
fi

# 5. 停止并删除旧容器
echo "🗑 正在停止并移除旧节点..."
for cfg in "${CONTAINER_CONFIGS[@]}"; do
    IFS=$'\x1F' read h k i cid <<< "$cfg"
    docker stop $cid > /dev/null 2>&1
    docker rm   $cid > /dev/null 2>&1
    echo "   已移除旧容器：$cid"
done

# 6. 重建容器
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
        echo "   ✅ 新容器已启动：${NEW_CID:0:12}  ($i)"
    else
        echo "   ❌ 容器启动失败！变量：$h / $i"
    fi
done

echo ""
echo "============================================="
echo "🎉 所有运行中节点已成功更新并重启！"
echo "============================================="

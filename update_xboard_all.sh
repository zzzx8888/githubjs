#!/bin/bash
IMAGE_NAME="ghcr.io/cedar2025/xboard-node:latest"

echo "============================================="
echo "  Xboard Node 全自动批量更新脚本"
echo "============================================="

CONTAINERS=$(docker ps -a --filter "ancestor=$IMAGE_NAME" -q)

if [ -z "$CONTAINERS" ]; then
    echo "未找到使用该镜像的容器"
    exit 1
fi

echo "找到容器数量：$(echo "$CONTAINERS" | wc -l)"
echo ""

declare -a CONTAINER_CONFIGS=()

for cid in $CONTAINERS
do
    echo "处理容器：$cid"
    apiHost=$(docker inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $cid | grep ^apiHost=)
    apiKey=$(docker inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $cid | grep ^apiKey=)
    nodeID=$(docker inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' $cid | grep ^nodeID=)
    echo " $apiHost"
    echo " $apiKey"
    echo " $nodeID"
    CONTAINER_CONFIGS+=("$apiHost|$apiKey|$nodeID")
done

echo "停止并删除旧容器..."
for cid in $CONTAINERS
do
    docker stop $cid
    docker rm $cid
done

echo "拉取最新镜像..."
docker pull $IMAGE_NAME

echo "重建容器..."
for cfg in "${CONTAINER_CONFIGS[@]}"
do
    IFS='|' read h k i <<< "$cfg"
    docker run -d --restart=always --network=host -e "$h" -e "$k" -e "$i" $IMAGE_NAME
done

echo "更新完成！"

#!/bin/bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$project_dir"

if [ ! -f "$project_dir/HeHongfrontend/dist/index.html" ]; then
    echo '部署失败：缺少 HeHongfrontend/dist/index.html。' >&2
    exit 1
fi

start_middleware() (
    services=(mysql redis rabbitmq)
    logs_pid=''

    stop_logs() {
        if [ -n "$logs_pid" ]; then
            kill "$logs_pid" 2>/dev/null || true
            wait "$logs_pid" 2>/dev/null || true
            logs_pid=''
        fi
    }
    # 只结束日志跟随，容器继续在后台运行；子 Shell 的 trap 不影响后续部署。
    trap stop_logs EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    echo '正在启动 MySQL、Redis、RabbitMQ…'
    if docker compose up -d --build "${services[@]}"; then
        :
    else
        status=$?
        docker compose logs --tail=100 --timestamps "${services[@]}" || true
        exit "$status"
    fi

    echo '正在显示中间件日志，等待健康检查通过（最长 300 秒）…'
    docker compose logs --follow --tail=100 --timestamps "${services[@]}" &
    logs_pid=$!

    # 容器已经启动；start --wait 使用 Compose 自身的健康检查等待逻辑。
    if docker compose --progress plain start --wait --wait-timeout 300 "${services[@]}"; then
        stop_logs
        echo '中间件已全部就绪，继续部署后端。'
    else
        status=$?
        stop_logs
        echo '中间件未能就绪，停止部署。以下为容器状态和最近日志：' >&2
        docker compose ps -a "${services[@]}" || true
        docker compose logs --tail=100 --timestamps "${services[@]}" || true
        exit "$status"
    fi
)

start_middleware

# 本次调用信任安装时已设置所有者的后端 Git 目录。
git_config_count=${GIT_CONFIG_COUNT:-0}
env "GIT_CONFIG_COUNT=$((git_config_count + 1))" \
    "GIT_CONFIG_KEY_${git_config_count}=safe.directory" \
    "GIT_CONFIG_VALUE_${git_config_count}=$project_dir/HeHongManage" \
    bash "$project_dir/HeHongManage/deploy.sh"

chmod 755 -- "$project_dir/HeHongfrontend"
docker compose up -d --build nginx

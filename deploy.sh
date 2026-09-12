#!/bin/bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
backend_dir="$project_dir/HeHongManage"
cd -- "$project_dir"
compose=(docker compose --project-directory "$project_dir" --file "$project_dir/docker-compose.yml")
middleware=(mysql redis rabbitmq)
backend=(web worker beat flower mcp-server)
mysql_log_pid=''

fail() { echo "部署失败：$*" >&2; exit 1; }
trap 'echo "部署未完成。" >&2' ERR

for command_name in git docker; do
    command -v "$command_name" >/dev/null || fail "缺少命令：$command_name。"
done
for required in docker-compose.yml .env HeHongManage/deploy.sh HeHongManage/.env nginx/default.conf; do
    [ -f "$project_dir/$required" ] || fail "缺少 $required。"
done
[ -f "$project_dir/HeHongfrontend/dist/index.html" ] || fail '缺少 HeHongfrontend/dist/index.html。'
docker compose version >/dev/null
docker info >/dev/null
"${compose[@]}" config --quiet
# 调用后端配置检查。
"${compose[@]}" run --rm --no-deps --entrypoint sh web -c '
    if [ "${DB_USERNAME:-}" = root ]; then
        echo "配置错误：DB_USERNAME 不能为 root。" >&2
        exit 1
    fi
    exec python ./config_check.py --require-pro
'

stop_mysql_logs() {
    if [ -n "$mysql_log_pid" ]; then
        kill "$mysql_log_pid" 2>/dev/null || true
        wait "$mysql_log_pid" 2>/dev/null || true
        mysql_log_pid=''
    fi
}
trap stop_mysql_logs EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

deploy_middleware() {
    local log_since
    log_since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    "${compose[@]}" up -d "${middleware[@]}"
    "${compose[@]}" logs --follow --since "$log_since" mysql &
    mysql_log_pid=$!
}

deploy_backend() {
    # 调用后端部署脚本。
    # 本次调用信任后端 Git 目录。
    local git_config_count=${GIT_CONFIG_COUNT:-0}
    env "GIT_CONFIG_COUNT=$((git_config_count + 1))" \
        "GIT_CONFIG_KEY_${git_config_count}=safe.directory" \
        "GIT_CONFIG_VALUE_${git_config_count}=$backend_dir" \
        bash "$backend_dir/deploy.sh"
}

update_frontend() {
    # 预留前端更新。
    :
}

deploy_frontend() {
    update_frontend
    "${compose[@]}" up -d --wait --wait-timeout 300 nginx
}

deploy_middleware
deploy_backend
deploy_frontend
stop_mysql_logs
"${compose[@]}" ps "${middleware[@]}" "${backend[@]}" nginx
echo '部署完成。'

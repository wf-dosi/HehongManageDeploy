#!/bin/bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
backend_dir="$project_dir/HeHongManage"
cd -- "$project_dir"
compose=(docker compose --project-directory "$project_dir" --file "$project_dir/docker-compose.yml")
middleware=(mysql redis rabbitmq)
backend=(web worker beat flower mcp-server)
wait_timeout=300

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

mysql_ready() {
    "${compose[@]}" exec -T mysql sh -c '
        MYSQL_PWD="$MYSQL_PASSWORD" mysql --connect-timeout=5 --protocol=TCP \
            -h127.0.0.1 -u"$MYSQL_USER" "$MYSQL_DATABASE" \
            --batch --skip-column-names -e "SELECT 1"
    ' >/dev/null 2>&1
}

redis_ready() {
    local response
    response=$("${compose[@]}" exec -T redis redis-cli ping 2>/dev/null) || return 1
    [ "${response//$'\r'/}" = PONG ]
}

rabbitmq_ready() {
    "${compose[@]}" exec -T rabbitmq rabbitmq-diagnostics -q -t 5 check_running >/dev/null 2>&1 &&
    "${compose[@]}" exec -T rabbitmq rabbitmq-diagnostics -q -t 5 check_port_connectivity >/dev/null 2>&1
}

web_ready() {
    "${compose[@]}" exec -T web python -c \
        'import socket; socket.create_connection(("127.0.0.1", 81), timeout=3).close()' >/dev/null 2>&1
}

wait_ready() {
    local service="$1" started=$SECONDS
    echo "等待 $service 就绪（最多 ${wait_timeout} 秒）……"
    until "${service}_ready"; do
        if (( SECONDS - started >= wait_timeout )); then
            "${compose[@]}" ps "$service" || true
            fail "$service 等待就绪超时。"
        fi
        sleep 2
    done
}

deploy_middleware() {
    "${compose[@]}" up -d --no-deps "${middleware[@]}"
    for service in "${middleware[@]}"; do
        wait_ready "$service"
    done
}

deploy_backend() {
    # 调用后端部署脚本。
    # 本次调用信任后端 Git 目录。
    local git_config_count=${GIT_CONFIG_COUNT:-0}
    env "GIT_CONFIG_COUNT=$((git_config_count + 1))" \
        "GIT_CONFIG_KEY_${git_config_count}=safe.directory" \
        "GIT_CONFIG_VALUE_${git_config_count}=$backend_dir" \
        bash "$backend_dir/deploy.sh"
    wait_ready web
}

update_frontend() {
    # 预留前端更新。
    :
}

deploy_frontend() {
    update_frontend
    "${compose[@]}" up -d --no-deps nginx
}

deploy_middleware
deploy_backend
deploy_frontend
"${compose[@]}" ps "${middleware[@]}" "${backend[@]}" nginx
echo '部署完成。'

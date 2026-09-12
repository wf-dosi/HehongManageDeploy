#!/bin/bash
set -euo pipefail
export NO_COLOR=1

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$project_dir"

if [ ! -f "$project_dir/HeHongfrontend/dist/index.html" ]; then
    echo '部署失败：缺少 HeHongfrontend/dist/index.html。' >&2
    exit 1
fi

docker compose up -d --build mysql redis rabbitmq

# 本次调用信任安装时已设置所有者的后端 Git 目录。
git_config_count=${GIT_CONFIG_COUNT:-0}
env "GIT_CONFIG_COUNT=$((git_config_count + 1))" \
    "GIT_CONFIG_KEY_${git_config_count}=safe.directory" \
    "GIT_CONFIG_VALUE_${git_config_count}=$project_dir/HeHongManage" \
    bash "$project_dir/HeHongManage/deploy.sh"

chmod 755 -- "$project_dir/HeHongfrontend"
docker compose up -d --build nginx

#!/bin/bash
set -euo pipefail
export NO_COLOR=1

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
backend_dir="$project_dir/HeHongManage"
backend_repo='git@gitee.com:znenghua/hehong_backend.git'
backend_branch='HeHongManage'
backend_image='my_flask_app'
cd -- "$project_dir"
compose=(docker compose --project-directory "$project_dir" --file "$project_dir/docker-compose.yml")

fail() { echo "安装失败：$*" >&2; exit 1; }
trap 'echo "安装未完成。" >&2' ERR

for command_name in git docker; do
    command -v "$command_name" >/dev/null || fail "缺少命令：$command_name。"
done
docker compose version >/dev/null
docker info >/dev/null
for required in docker-compose.yml .env.example; do
    [ -f "$project_dir/$required" ] || fail "缺少 $required。"
done

make_outer_env() (
    if [ -e "$project_dir/.env" ] || [ -L "$project_dir/.env" ]; then
        echo '已有外层 .env，保留原文件。'
        exit 0
    fi

    # 从 /dev/urandom 生成随机密码。
    umask 077
    content='' seen=''
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%$'\r'}
        line=${line#$'\xef\xbb\xbf'}
        case "$line" in
            DB_PASSWORD=*|MYSQL_ROOT_PASSWORD=*|RABBITMQ_PASSWORD=*)
                key=${line%%=*}
                [[ "$seen" != *"|$key|"* ]] || fail "外层模板配置重复：$key"
                password=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
                [[ "$password" =~ ^[0-9a-f]{64}$ ]] || fail '随机密码生成失败。'
                line="$key=$password"
                seen+="|$key|"
                ;;
        esac
        content+="$line"$'\n'
    done < "$project_dir/.env.example"
    for key in DB_PASSWORD MYSQL_ROOT_PASSWORD RABBITMQ_PASSWORD; do
        [[ "$seen" == *"|$key|"* ]] || fail "外层模板缺少密码配置项：$key"
    done

    # 完整生成后才写入；独占创建，避免并发安装覆盖已生成的密码。
    set -o noclobber
    printf '%s' "$content" > "$project_dir/.env"
    echo '已生成外层 .env。'
)

install_backend() {
    [ ! -L "$backend_dir" ] || fail '后端目录不能是符号链接。'
    if [ -e "$backend_dir" ]; then
        [ -e "$backend_dir/.git" ] || fail "HeHongManage 已存在但不是 Git 仓库。"
        echo '后端代码已存在，跳过克隆。'
    else
        git clone --depth 1 --branch "$backend_branch" --single-branch "$backend_repo" "$backend_dir"
    fi
    for required in Dockerfile docker-compose.yml deploy.sh make_env.sh config_check.py init.sh; do
        [ -f "$backend_dir/$required" ] || fail "后端缺少 $required。"
    done

    # 与应用容器的 UID/GID 一致；重复安装也修正已有后端目录。
    chown -hR -- 1000:1000 "$backend_dir" || fail '无法设置后端所有者为 1000:1000。'

    # 构建后端镜像，供后端 make_env 和应用运行使用。
    docker build --tag "$backend_image" "$backend_dir"

    [ -f "$project_dir/.env" ] || fail '外层 .env 未生成。'
    "${compose[@]}" config --quiet

    # env_file 注入外层中间件，后端 make_env 只生成应用配置和应用密钥。
    "${compose[@]}" run --rm --no-deps --user 1000:1000 \
        --entrypoint bash web ./make_env.sh
    [ -f "$backend_dir/.env" ] || fail '后端 .env 未生成。'
    chmod 640 -- "$backend_dir/.env"

}

install_frontend() {
    mkdir -p -- "$project_dir/HeHongfrontend/dist"
}

make_outer_env
install_backend
install_frontend
echo '安装完成，请继续完成环境配置'

#!/bin/bash
set -euo pipefail

ssh_dir="$HOME/.ssh"
key_file="$ssh_dir/id_ed25519"

fail() { echo "生成失败：$*" >&2; exit 1; }
command -v ssh-keygen >/dev/null || fail '缺少命令：ssh-keygen。'

if [ -e "$key_file" ] || [ -L "$key_file" ]; then
    [ -f "$key_file.pub" ] || fail '已有私钥，但缺少对应的 .pub 公钥文件。'
    echo '已有 SSH 密钥，保留原文件。'
elif [ -e "$key_file.pub" ] || [ -L "$key_file.pub" ]; then
    fail '已有公钥，但缺少对应私钥。'
else
    umask 077
    mkdir -p -- "$ssh_dir"
    chmod 700 -- "$ssh_dir"
    ssh-keygen -q -t ed25519 -N '' -f "$key_file" </dev/null
    echo 'SSH 密钥已生成。'
fi

printf '\nSSH 公钥：\n'
cat -- "$key_file.pub"

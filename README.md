# 物业平台运维

本仓库负责系统的一站式部署：准备后端代码和环境文件，启动中间件、后端与前端入口。

**首次部署顺序：准备仓库访问权限 → 安装 → 完成环境配置 → 部署启动。**
**后续版本更新：执行 `bash deploy.sh`。**

本文命令均在本仓库根目录执行。

## 生命周期总览

| 时间节点 | 操作 | 本阶段完成的工作 | 结束后的状态 |
| --- | --- | --- | --- |
| 首次安装前 | 准备运行环境与仓库访问权限 | 确保能够执行 Docker、Git 并读取后端仓库 | 可以开始安装 |
| 首次安装 | `bash install.sh` | 生成环境文件、克隆后端、设置所有者、构建镜像 | 代码和环境文件就位 |
| 安装完成后、首次启动前 | 完成环境配置 | 确认两份环境文件，前端产物位于固定目录 | 可以启动系统 |
| 首次启动 | `bash deploy.sh` | 启动中间件、调用后端部署、查看 Web 日志、设置前端目录权限、启动 nginx | 前后端进入运行阶段 |
| 后续版本更新 | `bash deploy.sh` | 更新后端、构建镜像、执行后续迁移、启动服务 | 按更新后的后端代码运行 |
| 日常运行 | 查看状态、日志，或启停已有容器 | 管理当前运行实例 | 保留已有代码、环境文件和数据 |
| 执行失败 | 修复报错后重跑对应脚本 | 继续安装或部署流程 | 以脚本结果和容器状态确认进度 |

## 1. 首次安装前

取得本仓库并进入根目录。运行环境需要具备：

- Linux、Bash、GNU coreutils（提供 `timeout`）、Git、OpenSSH、Docker Engine 和 Docker Compose v2。
- Docker 访问权限，以及将后端目录所有者设为 `1000:1000` 的权限。
- 后端仓库 `git@gitee.com:znenghua/hehong_backend.git` 的 SSH 读取权限。

需要生成 SSH 密钥时执行：

```bash
bash make_ssh_key.sh
```

脚本在当前用户的 `~/.ssh/` 下生成 `id_ed25519` 和 `id_ed25519.pub`，打印公钥供复制。已有密钥保留；密钥文件不完整时会报错。

将公钥配置为具有后端仓库读取权限的 SSH 公钥后，即可开始安装。密钥属于执行脚本的当前用户，Git 拉取使用执行 Git 的用户对应的 SSH 配置。

## 2. 首次安装：准备代码与环境文件

```bash
bash install.sh
```

安装按以下顺序执行：

1. 从 `.env.example` 生成外层 `.env`，用 Shell 随机生成数据库密码、MySQL root 密码和 RabbitMQ 密码。
2. 克隆后端仓库的 `HeHongManage` 分支到 `HeHongManage/`。
3. 检查后端部署文件，将后端目录所有者递归设置为 `1000:1000`。
4. 构建后端镜像并检查 Compose 配置。
5. 以 `1000:1000` 在一次性容器内调用后端 `make_env.sh`，生成 `HeHongManage/.env`。
6. 创建 `HeHongfrontend/dist/` 目录。

外层 `.env` 由 Shell 生成；后端应用配置由后端脚本在容器内生成。

**这个时间节点只完成代码、镜像和环境文件准备。中间件与应用服务尚未启动，数据库尚未初始化。**

安装结束提示：

> 安装完成，请继续完成环境配置

重复执行 `install.sh` 时，已有后端仓库跳过克隆，两份已有 `.env` 保留；仍会执行所有者设置、镜像构建和后端配置生成调用。后端代码更新由部署阶段处理。

## 3. 安装完成后：环境配置与前端产物

两份环境文件各自负责不同范围：

| 文件 | 负责范围 | 使用方式 |
| --- | --- | --- |
| `.env` | 外层中间件与部署参数 | Compose 使用，并通过 `env_file` 注入后端容器 |
| `HeHongManage/.env` | 后端应用配置与应用密钥 | 由后端加载与检查 |

外层已注入的中间件变量，后端生成配置时只保留注释，不重复保存对应值。

安装完成，请继续完成环境配置。

首次启动前，前端产物固定位于：

```text
HeHongfrontend/dist/
└── index.html
```

安装脚本创建前端目录，部署使用该目录内的现有产物。当前不自动拉取或构建前端。

## 4. 首次启动：中间件 → 后端 → 前端入口

```bash
bash deploy.sh
```

外层脚本依次执行：

1. 启动 MySQL、Redis、RabbitMQ，显示镜像拉取和容器创建进度；随后输出各服务最近 100 行日志并实时跟随，同时通过 `docker compose start --wait --wait-timeout 300 mysql redis rabbitmq` 等待健康检查。全部就绪后自动结束日志跟随并继续；日志进程及其子进程若在收到终止信号后 2 秒内未退出，则强制结束，不停止容器。失败或超时时打印状态与最近日志，停止部署。
2. 调用 `HeHongManage/deploy.sh`，由后端完成代码更新、构建和启动。Web 启动后实时显示本次启动日志；检测到 `Booting worker with pid:` 后自动结束跟随，再启动其余后端服务。已有健康容器输出最近 100 行日志后继续。日志中断或等待超过 300 秒仍未出现标记时停止部署。该标记表示 worker 开始启动。
3. `chmod 755 HeHongfrontend`。
4. `docker compose up -d --build nginx`。

### Web 启动期间：数据库初始化

数据库初始化发生在 **Web 容器启动期间**，由后端 `entrypoint.sh` 和 `init.sh` 负责。

| 后端迁移状态 | Web 启动时的行为 |
| --- | --- |
| 没有 `migrations/` | 检查数据库是否适合首次安装，创建迁移目录，执行迁移，初始化系统用户、默认超管及系统数据 |
| 存在 `.installing` 且没有 `.installed` | 重新进入初始化流程 |
| 已完成初始化，或已有完整迁移目录 | 执行后续迁移及系统初始化流程 |

首次初始化和后续迁移都会先将 `default_env.py` 覆盖到 `migrations/env.py`。迁移过程先应用已有迁移，再根据当前模型生成并应用迁移。

首次初始化成功后记录 `migrations/.installed`。外层脚本不直接执行 Flask 初始化命令。

## 5. 后续版本更新

```bash
bash deploy.sh
```

后续更新仍执行上述流程；Web 日志跟随在检测到 worker 启动标记后自动结束，随后继续部署，无需手动 Ctrl+C。

| 对象 | 再次部署时的处理 |
| --- | --- |
| 后端代码与镜像 | 拉取后端代码并重新构建 |
| 外层与后端 `.env` | 使用现有文件，不重新生成密码或应用密钥 |
| 数据库与迁移目录 | 基于已有状态执行迁移 |
| 前端产物 | 使用现有 `HeHongfrontend/dist`，设置前端目录权限后启动 nginx |
| 外层仓库代码 | 当前脚本不会拉取外层仓库自身 |

外层运维代码有更新时，先更新本仓库，再执行总 `deploy.sh`。

## 6. 日常运行与启停

`deploy.sh` 包含后端代码更新。管理已有容器时，可以直接使用以下命令：

| 场景 | 命令 |
| --- | --- |
| 查看全部容器状态 | `docker compose ps -a` |
| 查看 Web 日志 | `docker compose logs --tail=100 web` |
| 查看 nginx 日志 | `docker compose logs --tail=100 nginx` |
| 暂停全部服务 | `docker compose stop` |
| 启动已停止的容器 | `docker compose start` |
| 重启 Web 容器 | `docker compose restart web` |

`stop` 保留容器，`start` 启动已有容器；这两个操作不会执行后端的 Git 更新流程。[Docker Compose stop](https://docs.docker.com/reference/cli/docker/compose/stop/)、[start](https://docs.docker.com/reference/cli/docker/compose/start/)

Web 容器每次启动都会执行后端入口逻辑，已有安装进入后续迁移流程。`restart` 不会应用 Compose 环境变量等配置变更。[Docker Compose restart](https://docs.docker.com/reference/cli/docker/compose/restart/)

## 7. 失败后的处理节点

| 失败阶段 | 当前状态 | 后续入口 |
| --- | --- | --- |
| SSH 密钥或仓库访问 | 尚未取得后端代码 | 处理对应错误后执行 `bash install.sh` |
| 安装阶段 | 可能已生成环境文件或克隆代码，服务尚未由安装脚本启动 | 修复错误后执行 `bash install.sh` |
| 中间件启动 | 中间件可能已部分运行，尚未执行后端部署步骤 | 查看对应服务日志，修复后执行 `bash deploy.sh` |
| 后端更新或初始化 | 中间件已运行，后端可能处于更新或启动过程中 | 查看脚本错误及 Web 日志，修复后执行 `bash deploy.sh` |
| nginx 启动 | 后端已通过 Web 监听检查 | 查看 nginx 日志，修复后执行 `bash deploy.sh` |

脚本遇错停止，不自动回滚已经完成的步骤。重新执行安装会保留已有环境文件，重新执行部署仍会拉取后端代码。

## 8. 生命周期中的本地文件

| 路径 | 出现时间 | 用途 |
| --- | --- | --- |
| `.env` | 首次安装 | 外层中间件与部署配置 |
| `HeHongManage/` | 首次安装 | 后端代码及运行目录 |
| `HeHongManage/.env` | 首次安装 | 应用配置与应用密钥 |
| `HeHongfrontend/dist/` | 首次安装创建，部署前放入前端产物 | nginx 使用的前端产物 |
| `data/mysql/`、`data/redis/`、`data/rabbitmq/` | 中间件首次启动 | 中间件持久化数据 |
| `HeHongManage/migrations/` | 后端首次初始化 | 迁移脚本与安装状态 |

这些本地状态会在后续部署中继续使用，安装和部署脚本均没有清空数据目录的步骤。

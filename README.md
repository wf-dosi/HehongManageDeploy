# 物业平台运维

## 安装

```bash
bash install.sh
```

生成外层 `.env`，拉取后端代码，将后端目录所有者设为 `1000:1000`，构建镜像并调用后端 `make_env.sh`。
已有 `.env` 保留。

安装完成，请继续完成环境配置

## 部署

```bash
bash deploy.sh
```

检查配置，启动中间件，调用后端 `deploy.sh`，后端就绪后启动 nginx。
前端使用 `HeHongfrontend/dist`，更新逻辑预留在 `update_frontend()`。

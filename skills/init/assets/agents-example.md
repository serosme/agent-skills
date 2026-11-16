# 工作区

> 本文件由工作区初始化技能扫描生成，只在用户显式触发该技能重新扫描时更新；其他情况下不修改本文件，发现内容过时时说明差异并请用户重新运行初始化技能。重新扫描后无变化时不改动文件，说明 **无变化，未改本文件**。

## 现状

### 仓库

| 仓库          | 目录          |
| ------------- | ------------- |
| easy-cloud    | easy-cloud    |
| easy-cloud-ui | easy-cloud-ui |

### 服务

| 服务               | 仓库          | 用途                 | 地址                    |
| ------------------ | ------------- | -------------------- | ----------------------- |
| easy-cloud-gateway | easy-cloud    | 负责统一入口与路由。 | <http://localhost:8080> |
| easy-cloud-auth    | easy-cloud    | 负责登录与令牌校验。 | <http://localhost:8081> |
| easy-cloud-chat    | easy-cloud    | 提供对话接口。       | <http://localhost:8082> |
| easy-cloud-ui      | easy-cloud-ui | 提供工作台页面。     | <http://localhost:3000> |

### 基础设施

| 类型  | 主机      | 端口 | 库名或库号 |
| ----- | --------- | ---- | ---------- |
| mysql | localhost | 3306 | easy_cloud |
| redis | localhost | 6379 | 0          |

### 命令

| 命令                | 仓库          | 用途                 |
| ------------------- | ------------- | -------------------- |
| `pnpm install`      | easy-cloud-ui | 安装前端依赖         |
| `pnpm build`        | easy-cloud-ui | 构建并检查类型       |
| `./mvnw -q verify`  | easy-cloud    | 编译后端并跑单元测试 |
| `docker compose up` | easy-cloud    | 启动网关与后端服务   |
| `pnpm dev`          | easy-cloud-ui | 本地启动页面调试     |

## 约束

- 服务地址与端口必须取本文件的现状，不猜端口，不把地址硬编码进代码。
- 不要代为启动、重启、停止服务，不改端口，不结束进程，需要启动时由用户执行并回报实际地址。
- 改仓库文件、提交、推送、切分支前必须先征得用户同意，避免覆盖用户未提交的改动或把未完成的工作推给他人。
- 任何代码修改后必须执行对应仓库的命令，例如前端跑 `pnpm build`、后端跑 `./mvnw -q verify`，不得新增错误，并在回复中说明结果。

# AGENTS.md

本仓库唯一的人类规范与 AI 协作规则文件。

## 1. 项目定位

前端构建产物（`dist`）的发布脚本集合，两条通道：

- `deploy-docker.sh`：SSH 部署到远程 Docker 容器（备份 → 上传 → 解压 → 归档 → 重启）
- `upload-smb.sh`：上传构建包到文件服务器 SMB 共享目录

## 2. 目录结构

```
frontend-release-scripts/
├── deploy-docker.sh   # Docker 通道
├── upload-smb.sh      # 文件服务器通道
├── README.md          # 使用说明与项目元信息
├── AGENTS.md          # 本文件
└── CLAUDE.md          # 指向本文件的入口声明
```

新增脚本：放在仓库根目录，命名遵循 `动作-目标.sh`（如 `rollback-docker.sh`），同步在 README 的脚本清单登记。

## 3. 开发约束

1. **bash 3.2 兼容**：macOS 自带 bash 3.2，不使用关联数组（`declare -A`）、`${var,,}` 等 bash 4 特性。
2. **凭据不入库**：口令只通过环境变量传入（`SMB_USER` / `SMB_PASS` / `ENV_SMB_*`），脚本内不设默认值、不写明文。
3. **不切换调用方工作目录**：脚本按「构建产物所在目录」定位输入文件（`dist.tar.gz` / `dist.zip` / `dist/`）。
4. **配置区保持声明式**：`deploy-docker.sh` 的目标用 `add_target` 逐字段声明，不要退回长串 `|` 拼接。
5. **菜单实现重复**：两个脚本各自维护方向键菜单；修改一个时检查另一个。
6. **远程命令防注入**：拼进远程 shell 的变量（容器名等）先做字符集校验。
7. 本仓库无构建、无依赖安装步骤；不要引入 node/npm 之类运行时依赖。

## 4. 验证要求

- 每次改动至少执行：`bash -n <脚本>`。
- 涉及远程交互的改动（SSH、Docker、SMB），用桩脚本（假的 `ssh` / `sudo` / `docker`）构造端到端用例，不要在测试中连接真实环境。
- 菜单交互改动需在真实终端手动走一遍（↑/↓、j/k、回车、Ctrl+C）。

## 5. 部署流程

- 仓库自身不需要部署。
- 测试环境 / 生产环境由脚本配置或交互菜单决定，两处分别维护：
  - Docker：`deploy-docker.sh` 配置区 `add_target` 段
  - 文件服务器：`upload-smb.sh` 的 `select_target_dir` 路径列表
- 前端产物在对应项目仓库构建（如 `npm run build:web:CBMT` / `npm run buildcn`），再执行本仓库脚本分发。

## 6. 项目元信息

| 项 | 内容 |
| --- | --- |
| 原型地址 | 不适用（脚本仓库） |
| Jira 地址 | 待补充 |
| 测试服务 URL | Docker 目标机 `10.0.7.118`；文件服务器 `10.0.50.20`（共享 `yanfa-1`） |
| 部署流程 | 见第 5 节 |
| 账号密码 | SSH 密钥免密；SMB 凭据走环境变量，不入库；生产凭据不记录在本仓库 |

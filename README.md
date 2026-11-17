# frontend-release-scripts

前端构建产物的发布脚本集合：把 `dist` 产物分发到**远程 Docker 站点**与**文件服务器共享目录**两条通道。

## 脚本清单

| 脚本 | 作用 | 输入 | 目标 |
| --- | --- | --- | --- |
| `deploy-docker.sh` | SSH 部署到远程 Docker 容器：备份现有 dist → 清理旧包 → 上传 → 解压 → 归档 → 重启容器 | 当前目录的 `dist.tar.gz`；没有则由 `dist/` 自动打包 | `10.0.7.118` 上的 Docker 容器，目标在脚本「配置区」声明 |
| `upload-smb.sh` | 上传构建包到文件服务器 SMB 共享的指定目录 | 当前目录的 `dist.zip`；`--zip` 时先压缩 `dist/` | `10.0.50.20` 共享 `yanfa-1` 下交互选择的目录 |

两个脚本都用 ↑/↓（或 j/k）+ 回车选择目标；方向键菜单实现各自独立。

## 使用

脚本**在存放构建产物的目录下执行**（脚本不切换调用方工作目录），可把本仓库脚本软链到产物目录，或直接写绝对路径：

```bash
# 部署到 Docker（交互选择部署目标）
/path/to/deploy-docker.sh

# 跳过菜单：按序号或按显示名称
DEPLOY_TARGET=1 /path/to/deploy-docker.sh
DEPLOY_TARGET=19008_udpn_testapp /path/to/deploy-docker.sh

# 上传到文件服务器（交互选择路径）
/path/to/upload-smb.sh

# 当前目录没有 dist.zip 时，先把 dist/ 压缩成 dist.zip 再上传
/path/to/upload-smb.sh --zip
```

### deploy-docker.sh 配置

配置区每个目标一段 `add_target`，字段含义：

| 字段 | 含义 |
| --- | --- |
| `name` | 显示名称，也是 `DEPLOY_TARGET` 的取值 |
| `ssh_host` | `user@host` 或 `host` |
| `containers` | Docker 容器名；逗号串或连续多个取值 |
| `remote_path` | 远程部署目录 |
| `dist_path` | 远程部署包归档目录，省略时默认 `<remote_path>/dist` |
| `restart_cmd` | 自定义重启命令，在目标机原样执行（如 `cd /dir && sudo docker compose restart`）；省略时默认 `sudo docker restart <containers>` |

前置条件：目标机 SSH 密钥免密登录；`sudo` 可免密执行 `tar` / `mv` / `cp` / `rm` / `mkdir` / `docker`。

### upload-smb.sh 凭据

凭据不写入仓库、不设默认值，缺失即报错：

```bash
# 单次执行临时覆盖
SMB_USER=xxx SMB_PASS=xxx ./upload-smb.sh
```

或常驻 `~/.zshrc`：`export ENV_SMB_USER=xxx` / `export ENV_SMB_PASS=xxx`。

## 兼容性

- 按 macOS 自带 **bash 3.2** 编写（不使用关联数组等 bash 4 特性），Linux bash 4+ 同样可用。
- 依赖：`ssh` / `scp`（deploy）、`mount_smbfs` / `diskutil`（upload，仅 macOS）、`zip`（`--zip`）。

## 项目元信息

| 项 | 内容 |
| --- | --- |
| 原型地址 | 不适用（脚本仓库，无 UI 产物） |
| Jira 地址 | 待补充 |
| 测试服务 | Docker 目标机 `10.0.7.118`；文件服务器 `10.0.50.20`（共享 `yanfa-1`） |
| 部署流程 | 仓库自身无需部署；前端产物在项目仓库构建后，由本仓库脚本分发：Docker 通道走 `deploy-docker.sh`，文件服务器通道走 `upload-smb.sh` |
| 账号密码 | SSH 使用密钥免密；SMB 凭据通过环境变量提供，不入库 |

## 维护说明

- 两个脚本的交互菜单（隐藏光标 + ESC 序列解析 + 重绘）是重复实现，改其一需对照另一个是否需要同步。
- 本仓库不保存任何口令；提交前检查不要引入凭据。

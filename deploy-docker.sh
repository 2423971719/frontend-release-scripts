#!/bin/bash
#
# deploy-docker.sh
# 通过 SSH 将本地前端构建包部署到远程 Docker 容器
#
# 用法（在存放构建产物的目录下执行）：
#   ./deploy-docker.sh                         # 交互选择部署目标（↑/↓ 或 j/k 移动，回车确认）
#   DEPLOY_TARGET=1 ./deploy-docker.sh         # 按序号选择（1 起），跳过菜单
#   DEPLOY_TARGET=示例环境 ./deploy-docker.sh   # 按显示名称选择，跳过菜单
#
# 前置条件：
#   1. 已配置目标机 SSH 密钥免密登录（脚本不保存任何口令）
#   2. 目标机 sudo 可免密执行 tar / mv / cp / rm / mkdir / docker
#   3. 本地已构建（默认产物目录 dist/），或当前目录已有同名部署包
#
# 部署包：
#   当前目录存在 LOCAL_DIST_NAME 时直接使用；否则把 LOCAL_PATH 目录压缩成该包。
#   脚本自行生成的包在退出时清理；原本就存在的包不动。
#
# 配置：
#   部署目标在下方「配置区」用 add_target 声明，每个环境追加一段即可；
#   字段含义见配置区注释。
#
set -euo pipefail

# ============ 配置区 ============
# 每个目标一段 add_target，字段名在前、取值在后；新增环境复制一段改值即可。
#   name         显示名称（菜单展示，也可作为 DEPLOY_TARGET 的取值）
#   ssh_host     user@host 或 host；只写 host 时使用当前用户
#   containers   Docker 容器名；可写逗号串，也可连续写多个取值
#   remote_path  远程部署目录
#   dist_path    远程部署包归档目录；省略时默认 <remote_path>/dist
#   restart_cmd  自定义重启命令，在目标机原样执行（如 "cd /dir && sudo docker compose restart"）；
#                省略时默认 sudo docker restart <containers>
#
# 目标记录内部用 | 拼接保存，供菜单选择与解析使用；日常只改下面的 add_target 段。
DEPLOY_TARGETS=()

add_target() {
  local name="" ssh_host="" containers="" remote_path="" dist_path="" restart_cmd=""
  local list=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      name|ssh_host|restart_cmd|remote_path|dist_path)
        [[ $# -ge 2 ]] || { printf '[ERROR] add_target 字段 %s 缺少取值\n' "$1" >&2; exit 1; }
        printf -v "$1" '%s' "$2"   # 字段名与变量同名，按名字直接赋值
        shift 2
        ;;
      containers)
        # 容器名支持两种写法：containers "a,b" 或 containers "a" "b" "c"
        shift
        while [[ $# -gt 0 ]]; do
          case "$1" in
            name|ssh_host|containers|remote_path|dist_path|restart_cmd) break ;;
          esac
          list+=("$1")
          shift
        done
        if [[ "${#list[@]}" -gt 0 ]]; then
          containers=$(IFS=','; printf '%s' "${list[*]}")
        fi
        ;;
      *)
        printf '[ERROR] add_target 不认识的字段: %s\n' "$1" >&2
        exit 1
        ;;
    esac
  done

  # restart_cmd 放在记录最后一段：read 把余下内容整体交给最后一个变量，
  # 命令里带 | 也不会被截断
  DEPLOY_TARGETS+=("${name}|${ssh_host}|${containers}|${remote_path}|${dist_path:-${remote_path}/dist}|${restart_cmd}")
}

# ---- 目标：19008_udpn_testapp ----
add_target \
  name        "udpn_td_testapp" \
  ssh_host    "10.0.7.118" \
  containers  "19008_udpn_testapp" \
  remote_path "/root/docker-workspace/19008_udpn_testapp"

# ---- 目标：19007_udpn_testapp ----
add_target \
  name        "19007_udpn_testapp" \
  ssh_host    "10.0.7.118" \
  containers  "19007_udpn_testapp" \
  remote_path "/root/docker-workspace/19007_udpn_testapp"

# ---- 目标：cbmt-web-app-9001-5（5 个站点容器，由 docker compose 启动）----
add_target \
  name        "cbmt-web-app-9001-5" \
  ssh_host    "10.0.7.118" \
  containers  "cbmt-web-site-1-1" \
              "cbmt-web-site-2-1" \
              "cbmt-web-site-3-1" \
              "cbmt-web-site-4-1" \
              "cbmt-web-site-5-1" \
  remote_path "/root/docker-workspace/cbmt-web-app-9001-5" \
  restart_cmd "cd /root/docker-workspace/cbmt-web-app-9001-5 && sudo docker compose restart"

# ---- 目标：sbp_di_17024_5（2 个站点容器，由 docker compose 启动）----
add_target \
  name        "sbp_di_17024_5" \
  ssh_host    "10.0.7.118" \
  containers  "17024_sbp_di_portal" \
              "17025_sbp_di_operations" \
  remote_path "/root/docker-workspace/sbp_di_17024_5" \
  restart_cmd "cd /root/docker-workspace/sbp_di_17024_5 && sudo docker compose restart"

LOCAL_PATH="dist"              # 本地构建产物目录（相对当前执行目录）
LOCAL_DIST_NAME="dist.tar.gz"  # 本地部署包文件名
# ================================

# 颜色定义
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
NC=$'\033[0m'

# 日志函数
log_info()    { printf '%s[INFO]%s %s\n' "$BLUE" "$NC" "$*"; }
log_success() { printf '%s[SUCCESS]%s %s\n' "$GREEN" "$NC" "$*"; }
log_warning() { printf '%s[WARNING]%s %s\n' "$YELLOW" "$NC" "$*"; }
log_error()   { printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$*" >&2; }

error_exit() {
  log_error "$1"
  exit 1
}

# ---------- 部署目标选择（↑/↓ 移动高亮项，回车确认） ----------
select_target() {
  local total=${#DEPLOY_TARGETS[@]}
  local selected=0 key rest i first=1 name

  if [[ "$total" -eq 0 ]]; then
    error_exit "配置区没有部署目标，请先用 add_target 声明"
  fi

  echo ""
  echo "请选择部署目标（↑/↓ 或 j/k 移动，回车确认）："

  # 隐藏终端光标避免重绘闪烁；恢复放在 cleanup() 中，Ctrl+C 也能复原
  tput civis 2>/dev/null || true
  CURSOR_HIDDEN=1

  while :; do
    # 首次打印菜单；之后把光标移回菜单首行覆盖重绘
    if [[ "$first" -eq 1 ]]; then
      first=0
    else
      printf '\033[%dA\r' "$total"
    fi
    for i in "${!DEPLOY_TARGETS[@]}"; do
      name="${DEPLOY_TARGETS[$i]%%|*}"
      if [[ "$i" -eq "$selected" ]]; then
        printf '  \033[7m %2d) %s \033[0m\033[K\n' "$((i + 1))" "$name"
      else
        printf '    %2d) %s\033[K\n' "$((i + 1))" "$name"
      fi
    done

    # 方向键为 3 字节序列 ESC [ A/B：先读 1 字节，为 ESC 时再读余下 2 字节
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        IFS= read -rsn2 rest
        case "$rest" in
          '[A'|'A') selected=$(( (selected - 1 + total) % total )) ;;  # ↑（含 ESC O A 变体）
          '[B'|'B') selected=$(( (selected + 1) % total )) ;;          # ↓（含 ESC O B 变体）
        esac
        ;;
      'k'|'K') selected=$(( (selected - 1 + total) % total )) ;;  # vim 风格上移
      'j'|'J') selected=$(( (selected + 1) % total )) ;;          # vim 风格下移
      '') break ;;  # 回车确认
    esac
  done

  tput cnorm 2>/dev/null || true
  CURSOR_HIDDEN=0
  SELECTED_TARGET="${DEPLOY_TARGETS[$selected]}"
  echo ""
  echo ">> 已选择: $((selected + 1)) ${SELECTED_TARGET%%|*}"
}

# 解析目标记录并写入全局变量；字段缺失时明确报错
parse_target() {
  local record="$1"
  IFS='|' read -r TARGET_NAME SSH_HOST REMOTE_DOCKER_NAME REMOTE_PATH REMOTE_DIST_PATH REMOTE_RESTART_CMD <<<"$record"

  local missing=""
  if [[ -z "$TARGET_NAME" ]]; then missing+="显示名称 "; fi
  if [[ -z "$SSH_HOST" ]]; then missing+="SSH_HOST "; fi
  if [[ -z "$REMOTE_DOCKER_NAME" ]]; then missing+="Docker容器名 "; fi
  if [[ -z "$REMOTE_PATH" ]]; then missing+="远程部署目录 "; fi
  if [[ -z "$REMOTE_DIST_PATH" ]]; then missing+="远程部署包目录 "; fi
  if [[ -n "$missing" ]]; then
    error_exit "部署目标配置不完整，缺少字段: ${missing}
     解析出的记录: ${record}
     请检查该目标的 add_target 声明（name / ssh_host / containers / remote_path / dist_path）"
  fi

  # 容器名字段支持逗号或空格分隔的多个值，供重启阶段一次性 docker restart
  local raw_names="${REMOTE_DOCKER_NAME//,/ }"
  read -r -a REMOTE_DOCKER_NAMES <<<"$raw_names"

  local name
  if [[ "${#REMOTE_DOCKER_NAMES[@]}" -eq 0 ]]; then
    error_exit "Docker 容器名字段解析为空: ${REMOTE_DOCKER_NAME}"
  fi
  # 容器名会拼进远程 shell 命令，先限制字符集，避免引号/命令注入
  for name in "${REMOTE_DOCKER_NAMES[@]}"; do
    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
      error_exit "Docker 容器名不合法: ${name}
     只允许字母、数字、点、下划线、连字符，多个容器用逗号分隔"
    fi
  done
}

# 优先使用 DEPLOY_TARGET 环境变量（序号或名称），否则进入交互菜单
resolve_target() {
  local want="${DEPLOY_TARGET:-}"
  local total=${#DEPLOY_TARGETS[@]}
  local i name

  if [[ -z "$want" ]]; then
    select_target
    return 0
  fi

  for i in "${!DEPLOY_TARGETS[@]}"; do
    name="${DEPLOY_TARGETS[$i]%%|*}"
    if [[ "$want" == "$name" || "$want" == "$((i + 1))" ]]; then
      SELECTED_TARGET="${DEPLOY_TARGETS[$i]}"
      echo ""
      echo ">> 已选择: $((i + 1)) $name"
      return 0
    fi
  done

  error_exit "DEPLOY_TARGET=${want} 未匹配任何目标（可用序号 1-${total} 或显示名称）"
}

# ================================
# 执行目录与部署包路径（不切换工作目录）
EXEC_DIR="$(pwd)"
ZIP_FILE="${EXEC_DIR}/${LOCAL_DIST_NAME}"
SELECTED_TARGET=""
REMOTE_DOCKER_NAMES=()
REMOTE_RESTART_CMD=""
GENERATED_ARCHIVE=0
CURSOR_HIDDEN=0

# ---------- 清理 trap：恢复终端光标；仅删除本脚本生成的临时包 ----------
cleanup() {
  if [[ "$CURSOR_HIDDEN" -eq 1 ]]; then
    tput cnorm 2>/dev/null || true
  fi
  if [[ "$GENERATED_ARCHIVE" -eq 1 && -f "$ZIP_FILE" ]]; then
    echo ""
    echo ">> 清理本地临时部署包: ${ZIP_FILE}"
    rm -f -- "$ZIP_FILE"
  fi
}
trap cleanup EXIT

# ---------- 1. 准备本地部署包 ----------
prepare_local_archive() {
  log_info "检查本地部署包..."

  if [[ -f "$ZIP_FILE" ]]; then
    log_success "使用已有部署包: ${ZIP_FILE}"
    return 0
  fi

  if [[ ! -d "${EXEC_DIR}/${LOCAL_PATH}" ]]; then
    error_exit "未找到 ${ZIP_FILE}，也没有本地产物目录 ${EXEC_DIR}/${LOCAL_PATH}
     请先执行构建（如 npm run buildcn），或在存放部署包的目录下执行本脚本"
  fi

  log_info "压缩 ${LOCAL_PATH}/ -> ${LOCAL_DIST_NAME} ..."
  (cd "$EXEC_DIR" && tar -czf "$LOCAL_DIST_NAME" "$LOCAL_PATH")
  GENERATED_ARCHIVE=1
  log_success "压缩完成: $(du -h "$ZIP_FILE" | awk '{print $1}')"
}

# ---------- 2. 检查 SSH 连接 ----------
check_ssh_connection() {
  log_info "检查 SSH 连接: ${SSH_HOST} ..."

  # BatchMode=yes：免密登录未配置时立即失败，而不是卡在密码提示
  if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$SSH_HOST" "true" >/dev/null 2>&1; then
    error_exit "SSH 连接失败: ${SSH_HOST}
     请确认目标机可达、密钥免密登录已配置（BatchMode 下不会提示输入密码）"
  fi
  log_success "SSH 连接正常"
}

# ---------- 3. 检查远程目录 ----------
check_remote_directory() {
  log_info "检查远程目录: ${REMOTE_PATH} ..."

  if ! ssh "$SSH_HOST" "sudo [ -d '${REMOTE_PATH}' ]"; then
    error_exit "远程目录不存在: ${REMOTE_PATH}
     请先在目标机创建该目录，或检查 sudo 权限"
  fi
  log_success "远程目录存在"
}

# ---------- 4. 检查 Docker 容器 ----------
check_docker_containers() {
  log_info "检查 Docker 容器: ${REMOTE_DOCKER_NAMES[*]} ..."

  local missing=() name
  for name in "${REMOTE_DOCKER_NAMES[@]}"; do
    if ! ssh "$SSH_HOST" "sudo docker ps -a --format '{{.Names}}' | grep -qxF '${name}'"; then
      missing+=("$name")
    fi
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    error_exit "Docker 容器不存在: ${missing[*]}"
  fi
  log_success "Docker 容器存在"
}

# ---------- 5. 备份当前部署 ----------
backup_current_deployment() {
  log_info "备份当前部署..."

  local backup_dir="${REMOTE_PATH}/backup_$(date +%Y%m%d_%H%M%S)"
  if ssh "$SSH_HOST" "sudo [ -d '${REMOTE_PATH}/dist' ]" 2>/dev/null; then
    if ssh "$SSH_HOST" "sudo cp -r '${REMOTE_PATH}/dist' '${backup_dir}'" 2>/dev/null; then
      log_success "备份创建成功: ${backup_dir}"
    else
      log_warning "备份创建失败，继续部署..."
    fi
  else
    log_info "没有找到现有 dist 部署，跳过备份"
  fi
}

# ---------- 6. 清理远程旧部署包 ----------
cleanup_remote_files() {
  log_info "清理远程旧部署包..."

  if ssh "$SSH_HOST" "sudo rm -f '${REMOTE_PATH}/${LOCAL_DIST_NAME}'"; then
    log_success "旧部署包清理完成"
  else
    log_warning "清理旧部署包时出现警告，继续执行..."
  fi
}

# ---------- 7. 上传部署包 ----------
upload_files() {
  log_info "上传部署包..."

  local start_time end_time duration
  start_time=$(date +%s)

  # 先上传到远程用户 home 目录，再用 sudo 移动到目标目录
  if ! scp -o ConnectTimeout=30 "$ZIP_FILE" "${SSH_HOST}:~/"; then
    error_exit "上传失败: scp ${ZIP_FILE} -> ${SSH_HOST}:~/"
  fi
  if ! ssh "$SSH_HOST" "sudo mv -f ~/$(basename -- "$LOCAL_DIST_NAME") '${REMOTE_PATH}/${LOCAL_DIST_NAME}'"; then
    error_exit "移动到远程目录失败: ${REMOTE_PATH}/${LOCAL_DIST_NAME}"
  fi

  end_time=$(date +%s)
  duration=$((end_time - start_time))
  log_success "上传并移动完成 (耗时: ${duration}s)"
}

# ---------- 8. 解压部署包 ----------
extract_files() {
  log_info "解压部署包到 ${REMOTE_PATH} ..."

  if ! ssh "$SSH_HOST" "sudo tar -xzf '${REMOTE_PATH}/${LOCAL_DIST_NAME}' -C '${REMOTE_PATH}'"; then
    error_exit "解压失败: ${REMOTE_PATH}/${LOCAL_DIST_NAME}"
  fi
  log_success "解压完成"
}

# ---------- 9. 归档部署包 ----------
move_files() {
  log_info "归档部署包到 ${REMOTE_DIST_PATH} ..."

  if ! ssh "$SSH_HOST" "sudo mkdir -p '${REMOTE_DIST_PATH}' && sudo mv -f '${REMOTE_PATH}/${LOCAL_DIST_NAME}' '${REMOTE_DIST_PATH}/'"; then
    error_exit "部署包归档失败: ${REMOTE_DIST_PATH}"
  fi
  log_success "部署包归档完成"
}

# ---------- 10. 重启 Docker 容器 ----------
restart_docker_containers() {
  local quoted="" name

  if [[ -n "$REMOTE_RESTART_CMD" ]]; then
    # 自定义命令按目标配置，原样交给目标机 shell 执行（如 docker compose restart）
    log_info "执行自定义重启命令: ${REMOTE_RESTART_CMD}"
    if ! ssh "$SSH_HOST" "$REMOTE_RESTART_CMD"; then
      error_exit "自定义重启命令执行失败: ${REMOTE_RESTART_CMD}"
    fi
  else
    log_info "重启 Docker 容器: ${REMOTE_DOCKER_NAMES[*]} ..."

    # 多个容器合并为一条 docker restart 命令，一次 SSH 往返完成
    for name in "${REMOTE_DOCKER_NAMES[@]}"; do
      quoted+=" '${name}'"
    done

    if ! ssh "$SSH_HOST" "sudo docker restart${quoted}"; then
      error_exit "Docker 容器重启失败: ${REMOTE_DOCKER_NAMES[*]}"
    fi
  fi

  log_info "等待容器启动..."
  sleep 3

  # 一次取回全部运行中容器的「名字|状态」，再逐个对账
  local ps_output container_status
  ps_output=$(ssh "$SSH_HOST" "sudo docker ps --format '{{.Names}}|{{.Status}}'" || true)
  for name in "${REMOTE_DOCKER_NAMES[@]}"; do
    container_status=$(awk -F'|' -v n="$name" '$1 == n { print $2 }' <<<"$ps_output")
    if [[ "$container_status" == Up* ]]; then
      log_success "Docker 容器运行中: ${name} (${container_status})"
    else
      log_warning "Docker 容器状态异常: ${name} (${container_status:-未在运行列表})"
    fi
  done
}

# 主函数
main() {
  log_info "开始部署流程..."
  local start_time end_time total_duration
  start_time=$(date +%s)

  resolve_target
  parse_target "$SELECTED_TARGET"

  log_info "部署目标: ${TARGET_NAME}"
  log_info "   SSH: ${SSH_HOST}"
  log_info "   容器: ${REMOTE_DOCKER_NAMES[*]}"
  log_info "   目录: ${REMOTE_PATH}"
  log_info "   归档: ${REMOTE_DIST_PATH}"
  if [[ -n "$REMOTE_RESTART_CMD" ]]; then
    log_info "   重启: ${REMOTE_RESTART_CMD}"
  else
    log_info "   重启: sudo docker restart ${REMOTE_DOCKER_NAMES[*]}"
  fi

  # 前置检查
  prepare_local_archive
  check_ssh_connection
  check_remote_directory
  check_docker_containers

  # 部署流程
  backup_current_deployment
  cleanup_remote_files
  upload_files
  extract_files
  move_files
  restart_docker_containers

  end_time=$(date +%s)
  total_duration=$((end_time - start_time))
  echo ""
  log_success "部署完成: ${TARGET_NAME} (${SSH_HOST} / ${REMOTE_DOCKER_NAMES[*]})"
  log_success "总耗时: ${total_duration}s"
}

main "$@"

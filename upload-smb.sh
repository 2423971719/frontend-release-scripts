#!/usr/bin/env bash
#
# upload-smb.sh
# 上传 dist.zip 到文件服务器 10.0.50.20（SMB 共享 yanfa-1）
# 目标目录: 运行时交互选择（↑/↓ 或 j/k 移动，回车确认；共 10 个可选路径）
#
# 等价于：访达 -> 前往 -> 连接服务器 -> smb://10.0.50.20/yanfa-1，然后拷贝文件
#
# 用法（在存放 dist.zip 的目录下执行，脚本会在当前目录寻找 dist.zip）:
#   ./upload-smb.sh            # 直接上传当前目录下已有的 dist.zip
#   ./upload-smb.sh --zip      # 先将当前目录下 dist/ 压缩为 dist.zip 再上传
#
# 凭据来源（优先级从高到低；不设默认值，未提供则报错退出）:
#   1. SMB_USER=xxx SMB_PASS=xxx ./upload-smb.sh   # 单次执行时临时覆盖
#   2. 全局 export 的 ENV_SMB_USER / ENV_SMB_PASS（定义在 ~/.zshrc）
#
set -euo pipefail

# ============ 配置区 ============
SMB_SERVER="10.0.50.20"
SMB_SHARE="yanfa-1"
# 凭据：单次 SMB_* 覆盖 > 全局 ENV_SMB_*；无默认值，缺失即报错（注意 set -e 下收集缺失项须用 if，不能用 [[ ]] && 短路）
SMB_USER="${SMB_USER:-${ENV_SMB_USER:-}}"
SMB_PASS="${SMB_PASS:-${ENV_SMB_PASS:-}}"

MISSING=""
if [[ -z "$SMB_USER" ]]; then MISSING="SMB_USER"; fi
if [[ -z "$SMB_PASS" ]]; then MISSING="${MISSING:+${MISSING} }SMB_PASS"; fi
if [[ -n "$MISSING" ]]; then
  echo "错误: 未设置 SMB 凭据变量: ${MISSING}（无默认值兜底）" >&2
  echo "请任选其一：" >&2
  echo "  1. 在 ~/.zshrc 中 export ENV_SMB_USER / ENV_SMB_PASS，然后重开终端或执行 source ~/.zshrc" >&2
  echo "  2. 本次执行时临时指定: SMB_USER=xxx SMB_PASS=xxx ./upload-smb.sh" >&2
  exit 1
fi

# ---------- 上传路径选择（↑/↓ 移动高亮项，回车确认） ----------
select_target_dir() {
  local options=(
    "hainan-gch/海南二期测试环境/门户前端"
    "hainan-gch/海南二期测试环境/运营前端"
    "hainan-gch/海南二期生产环境/门户前端"
    "hainan-gch/海南二期生产环境/运营前端"
    "SBP-DI/前端/门户"
    "SBP-DI/前端/运营"
    "SBP/门户前端"
    "SBP/运营前端"
    "广东联通/门户前端"
    "广东联通/运营前端"
    "广东联通/fisco浏览器"
    "UDPN/TD-Web-App/前端"
  )
  local total=${#options[@]}
  local selected=0 key rest i first=1

  echo ""
  echo "请选择要上传的路径（↑/↓ 或 j/k 移动，回车确认）："

  # 隐藏终端光标避免重绘闪烁；恢复放在 cleanup() 中，Ctrl+C 也能复原
  tput civis 2>/dev/null || true

  while :; do
    # 首次打印菜单；之后把光标移回菜单首行覆盖重绘
    if [[ "$first" -eq 1 ]]; then
      first=0
    else
      printf '\033[%dA\r' "$total"
    fi
    for i in "${!options[@]}"; do
      if [[ "$i" -eq "$selected" ]]; then
        printf '  \033[7m %2d) %s \033[0m\033[K\n' "$((i + 1))" "${options[$i]}"
      else
        printf '    %2d) %s\033[K\n' "$((i + 1))" "${options[$i]}"
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
  REMOTE_SUBDIR="${options[$selected]}"
  echo ""
  echo ">> 已选择: ${REMOTE_SUBDIR}"
}

# ================================

# 在脚本执行目录下寻找 dist.zip（不切换工作目录）
EXEC_DIR="$(pwd)"
ZIP_FILE_NAME="dist.zip"
ZIP_FILE="${EXEC_DIR}/${ZIP_FILE_NAME}"

# ---------- 清理 trap：异常退出时卸载并删除临时挂载点 ----------
MOUNTED_BY_US=0
MOUNT_POINT=""
cleanup() {
  tput cnorm 2>/dev/null || true   # 恢复终端光标（菜单选择期间被隐藏）
  if [[ "$MOUNTED_BY_US" -eq 1 && -n "$MOUNT_POINT" ]]; then
    umount "$MOUNT_POINT" 2>/dev/null || diskutil unmount force "$MOUNT_POINT" 2>/dev/null || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# 交互选择上传路径（放在 trap 注册之后，确保选择阶段 Ctrl+C 也能恢复终端状态）
select_target_dir

# ---------- 1. 准备 dist.zip ----------
if [[ ! -f "$ZIP_FILE" ]]; then
  if [[ "${1:-}" == "--zip" && -d "${EXEC_DIR}/dist" ]]; then
    echo ""
    echo ">> 未找到 dist.zip，正在压缩 ${EXEC_DIR}/dist/ -> dist.zip ..."
    (cd "${EXEC_DIR}/dist" && zip -rq "${ZIP_FILE}" . -x ".DS_Store" -x "*/.DS_Store")
    echo ""
    echo ">> 压缩完成: $(du -h "$ZIP_FILE" | awk '{print $1}')"
  else
    echo ""
    echo "错误: 未找到 ${ZIP_FILE}" >&2
    echo ""
    echo "提示: 请在存放 dist.zip 的目录下执行本脚本；或先执行构建（npm run buildcn），或加 --zip 参数自动压缩 dist/ 后上传" >&2
    exit 1
  fi
fi

# ---------- 2. 挂载 SMB 共享 ----------
# 注意: macOS 下普通用户无法在 /Volumes 下建目录（firmlink 保护），
# 所以挂载点用临时目录；仅当 Finder 已挂载 /Volumes/Public 时复用它。
FINDER_MP="/Volumes/${SMB_SHARE}"
if mount | grep -q " on ${FINDER_MP} "; then
  MOUNT_POINT="$FINDER_MP"
  echo ""
  echo ">> 检测到 Finder 已挂载共享: ${MOUNT_POINT}（复用现有挂载）"
else
  MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/smb-${SMB_SHARE}.XXXXXX")"
  echo ""
  echo ">> 挂载 smb://${SMB_USER}@${SMB_SERVER}/${SMB_SHARE} -> ${MOUNT_POINT} ..."
  mount_smbfs "//${SMB_USER}:${SMB_PASS}@${SMB_SERVER}/${SMB_SHARE}" "$MOUNT_POINT"
  MOUNTED_BY_US=1
fi

# ---------- 3. 拷贝文件 ----------
TARGET_DIR="${MOUNT_POINT}/${REMOTE_SUBDIR}"
mkdir -p "$TARGET_DIR"

# 上传前先删除目标目录中已存在的同名文件，确保干净替换（避免 SMB 覆盖异常/残留旧包）
if [[ -e "${TARGET_DIR}/${ZIP_FILE_NAME}" ]]; then
  echo ""
  echo ">> 删除旧文件: ${REMOTE_SUBDIR}/${ZIP_FILE_NAME}"
  rm -f "${TARGET_DIR}/${ZIP_FILE_NAME}"
fi

echo ""
echo ">> 上传 ${ZIP_FILE} -> //${SMB_SERVER}/${SMB_SHARE}/${REMOTE_SUBDIR}/"

cp -f "$ZIP_FILE" "$TARGET_DIR/"

ls -lh "${TARGET_DIR}/${ZIP_FILE_NAME}"

echo ""
echo "✅ 上传完成: //${SMB_SERVER}/${SMB_SHARE}/${REMOTE_SUBDIR}/${ZIP_FILE_NAME}"

# ---------- 4. 卸载（trap 会执行；仅卸载本脚本挂载的，不动 Finder 的） ----------
if [[ "$MOUNTED_BY_US" -eq 1 ]]; then
  echo ""
  echo ">> 卸载 ${MOUNT_POINT} ..."
  umount "$MOUNT_POINT" 2>/dev/null || diskutil unmount force "$MOUNT_POINT" || true
  rmdir "$MOUNT_POINT" 2>/dev/null || true
  MOUNTED_BY_US=0
  echo ""
  echo ">> 已卸载"
fi

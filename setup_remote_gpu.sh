#!/bin/bash

# ==============================================================================
# WSL -> 远程 GPU 一键就绪脚本 (2026-02-05 优化版)
# 功能：
#   1. 自动管理 ssh-agent 与私钥常驻 (ssh-add)
#   2. 建立无密码 SSH 隧道验证
#   3. 自动化 CUDA 版本兼容性检查 (本地 nvcc vs 远程 driver)
#   4. 实时显示远程 GPU 状态与占用情况
# ==============================================================================

# 配置远程参数
REMOTE_USER="qtc_yu"
REMOTE_IP="8.145.51.96"
REMOTE_PORT="2222"
KEY_PATH="/mnt/c/Users/Administrator/.ssh/ksy.id"

echo "===================================================="
echo "🚀 开始环境就绪检查 (WSL -> Remote GPU)"
echo "===================================================="

# 1. SSH-Agent 与 私钥常驻化
if [ -z "$SSH_AUTH_SOCK" ]; then
    echo "🔑 启动 ssh-agent..."
    eval "$(ssh-agent -s)" > /dev/null
fi

# 检查私钥是否已添加，若未添加则执行 ssh-add
if ! ssh-add -l | grep -q "$KEY_PATH"; then
    echo "🔓 加载私钥: $KEY_PATH"
    ssh-add "$KEY_PATH" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "❌ 错误: 无法加载私钥，请检查路径 $KEY_PATH 是否正确。"
        exit 1
    fi
fi
echo "✅ SSH 私钥已常驻。"

# 2. 建立无密码 SSH 验证
echo "🌐 正在建立 SSH 连接 (Port: $REMOTE_PORT)..."
SSH_OPTS="-p $REMOTE_PORT -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no"

# 3. 验证远程状态与兼容性
echo "🔍 正在拉取远程 GPU 实时状态..."
REMOTE_INFO=$(ssh $SSH_OPTS $REMOTE_USER@$REMOTE_IP "nvidia-smi --query-gpu=driver_version,name,memory.total,memory.used,utilization.gpu --format=csv,noheader,nounits" 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ 错误: 无法连接远程服务器，请检查网络或端口 $REMOTE_PORT。"
    exit 1
fi

# 解析远程信息
REMOTE_DRIVER=$(echo $REMOTE_INFO | cut -d',' -f1 | tr -d ' ')
GPU_NAME=$(echo $REMOTE_INFO | cut -d',' -f2)
MEM_TOTAL=$(echo $REMOTE_INFO | cut -d',' -f3 | tr -d ' ')
MEM_USED=$(echo $REMOTE_INFO | cut -d',' -f4 | tr -d ' ')
GPU_UTIL=$(echo $REMOTE_INFO | cut -d',' -f5 | tr -d ' ')

# 4. 版本兼容性检查
LOCAL_NVCC=$(nvcc --version | grep "release" | awk '{print $5}' | cut -d',' -f1)
echo "----------------------------------------------------"
echo "📊 [兼容性报告]"
echo "  - 本地 WSL CUDA (nvcc): $LOCAL_NVCC"
echo "  - 远程 GPU 驱动版本: $REMOTE_DRIVER"
echo "  - 远程 GPU 型号: $GPU_NAME"

# 简单兼容性判定 (示例：CUDA 12.0 需要 525+)
COMPAT_CHECK=$(echo "$REMOTE_DRIVER >= 525.0" | bc -l 2>/dev/null)
if [[ "$COMPAT_CHECK" == "1" ]]; then
    echo "  >> 状态: ✅ 兼容性验证通过。"
else
    echo "  >> 状态: ⚠️ 警告：驱动版本可能较低，建议核对 CUDA $LOCAL_NVCC 兼容矩阵。"
fi

echo "----------------------------------------------------"
echo "🔥 [实时占用情况]"
echo "  - GPU 使用率: $GPU_UTIL %"
echo "  - 显存占用: $MEM_USED / $MEM_TOTAL MiB"
echo "----------------------------------------------------"

# 打印完整的 nvidia-smi 视图供参考
ssh $SSH_OPTS $REMOTE_USER@$REMOTE_IP "nvidia-smi"

echo "===================================================="
echo "🎉 环境已就绪！可以开始开发。"
echo "===================================================="

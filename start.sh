#!/bin/bash
# DeePAW 一键启动脚本
# 用法: ./start.sh [可选: 挂载的数据目录]

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DRIVER_VER=$(cat /sys/module/nvidia/version 2>/dev/null || echo "525.60.13")
DATA_DIR="${1:-/home/sutianhao/data/podman/to8022/ckp/deepaw_iso/deepaw/rep_sub_model/check_pred_MP/asedb}"
OUTPUT_DIR="${SCRIPT_DIR}/output"

mkdir -p "$OUTPUT_DIR"

podman run -it --rm \
  --security-opt=label=disable \
  --device /dev/nvidia0 \
  --device /dev/nvidiactl \
  --device /dev/nvidia-uvm \
  --device /dev/nvidia-uvm-tools \
  --device /dev/nvidia-modeset \
  -v "/usr/lib64/libnvidia-ml.so.${DRIVER_VER}:/usr/lib64/libnvidia-ml.so.${DRIVER_VER}:ro" \
  -v "/usr/lib64/libcuda.so.${DRIVER_VER}:/usr/lib64/libcuda.so.${DRIVER_VER}:ro" \
  -v "/usr/lib64/libnvidia-ptxjitcompiler.so.${DRIVER_VER}:/usr/lib64/libnvidia-ptxjitcompiler.so.${DRIVER_VER}:ro" \
  -e PYTHONPATH=/app/deepaw \
  -e "LD_LIBRARY_PATH=/app/deepaw:/usr/local/lib/python3.12/dist-packages/torch/lib:/usr/lib64" \
  -v "${DATA_DIR}:/data" \
  -v "${OUTPUT_DIR}:/output" \
  deepaw-cpp:v1 \
  bash

# DeePAW C++ 推理引擎 - 容器版

> 机器: `amsera02` (to8022) | 用户: `sutianhao` | 路径: `/scratch/sutianhao/data/podman/to8022/deepaw_cpp_docker/`
> 镜像 tar 包 (6.1GB) 未上传 GitHub，保存在上述路径的 `deepaw_dist_v1_cpp/deepaw-cppv1.tar.gz`

容器化的 DeePAW C++ 推理引擎，解决 glibc/C库版本依赖问题，可在不同 Linux 机器上直接运行。

## 快速开始

### 1. 加载镜像（首次使用）

```bash
# 检查镜像是否已加载
podman images | grep deepaw

# 没有的话，加载（约1-2分钟）
podman load -i deepaw_dist_v1_cpp/deepaw-cppv1.tar.gz
# 输出: Loaded image: localhost/deepaw-cpp:latest
```

### 2. 一键启动

```bash
cd /scratch/sutianhao/data/podman/to8022/deepaw_cpp_docker
./start.sh
```

进入容器后会看到彩虹欢迎界面，然后运行推理：

```bash
# 内置测试数据
python predict_chgcar.py --db tests/hfo2.db --id 1 --device cuda

# 使用挂载的自定义数据（默认挂载到 /data）
python predict_chgcar.py --db /data/your.db --id 1 --device cuda

# 指定输出路径（/output 挂载到宿主机 output/ 目录）
python predict_chgcar.py --db /data/your.db --id 1 --device cuda --output /output/CHGCAR_结果

# 自定义网格密度
python predict_chgcar.py --db /data/your.db --id 1 --device cuda --grid 60 60 60
```

退出容器后，输出文件在宿主机的 `output/` 目录。

### 3. 挂载不同的数据目录

```bash
./start.sh /path/to/your/data
```

## 镜像版本说明

| Tag | 说明 |
|-----|------|
| `deepaw-cpp:v1` | 最终版本，有欢迎界面（`start.sh` 默认使用） |
| `deepaw-cpp:latest` | 早期调试版本，无欢迎界面 |

## 重要注意事项

### 只支持 CUDA，不支持 CPU

加密模型的解密逻辑编译在 C++ 引擎里，只能在 CUDA 设备上初始化。
`--device cpu` 会导致模型初始化静默失败。

### GPU 透传方式

本机（Rocky Linux 9.2）上 CDI 方式（`--device nvidia.com/gpu=all`）不能正常工作。
`start.sh` 已自动处理：手动挂载 `/dev/nvidia*` 设备和宿主机 NVIDIA `.so` 库，并自动检测驱动版本。

如果驱动升级后出问题，确认版本：
```bash
cat /sys/module/nvidia/version
# 或
nvidia-smi | head -3
```

### 环境变量

容器内必须设置 `PYTHONPATH` 和 `LD_LIBRARY_PATH`，`start.sh` 已自动处理。
如果手动 `podman run`，必须加：
```
-e PYTHONPATH=/app/deepaw
-e LD_LIBRARY_PATH=/app/deepaw:/usr/local/lib/python3.12/dist-packages/torch/lib:/usr/lib64
```

## 容器内部结构

```
/app/
├── predict_chgcar.py          # 主推理脚本
├── deepaw/
│   ├── __init__.py            # Python API (Model/SecureModel)
│   ├── deepaw_cpp.*.so        # pybind11 C++ 绑定
│   ├── libdeepaw_core.so      # C++ 核心库（解密密钥在此）
│   └── data/                  # 图构建工具
├── models/
│   ├── f_nonlocal.enc         # 加密的 GNN 模型 (~20MB)
│   └── f_local.enc            # 加密的 KAN 校正模型 (~300KB)
├── tests/hfo2.db              # 内置测试数据
└── welcome.sh                 # 欢迎界面
```

## 环境信息

| 项目 | 值 |
|------|-----|
| 宿主机 OS | Rocky Linux 9.2 |
| 宿主机 GLIBC | 2.34 |
| 容器基础镜像 | nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 |
| 容器 GLIBC | 2.35 |
| Python | 3.12 |
| GPU | NVIDIA GeForce RTX 4090 (24GB) |
| NVIDIA Driver | 525.60.13 |
| nvidia-container-toolkit | 1.18.1 |

HfO2 测试（id=1, 40x40x40 网格, 64000 点, 64 批次）：RTX 4090 约 27 秒。

## 手动运行（不用 start.sh 的情况）

如果 `start.sh` 不适用（比如在其他机器上），可以手动运行：

```bash
podman run -it --rm \
    --security-opt=label=disable \
    --device /dev/nvidia0 \
    --device /dev/nvidiactl \
    --device /dev/nvidia-uvm \
    --device /dev/nvidia-uvm-tools \
    --device /dev/nvidia-modeset \
    -v /usr/lib64/libnvidia-ml.so.<版本号>:/usr/lib64/libnvidia-ml.so.<版本号>:ro \
    -v /usr/lib64/libcuda.so.<版本号>:/usr/lib64/libcuda.so.<版本号>:ro \
    -v /usr/lib64/libnvidia-ptxjitcompiler.so.<版本号>:/usr/lib64/libnvidia-ptxjitcompiler.so.<版本号>:ro \
    -e PYTHONPATH=/app/deepaw \
    -e LD_LIBRARY_PATH=/app/deepaw:/usr/local/lib/python3.12/dist-packages/torch/lib:/usr/lib64 \
    -v /path/to/your/data:/data \
    -v $(pwd)/output:/output \
    deepaw-cpp:v1 \
    bash
```

查找驱动版本号：`cat /sys/module/nvidia/version` 或 `ls /usr/lib64/libcuda.so.*`

## 构建镜像（开发用）

一般不需要重新构建，直接用预构建的 tar 包加载即可。如需重建：

```bash
./build.sh
```

## 镜像分发

```bash
# 导出
podman save deepaw-cpp:v1 | gzip > deepaw-cpp-v1.tar.gz

# 在其他机器加载
gunzip -c deepaw-cpp-v1.tar.gz | podman load

# 验证
podman images | grep deepaw-cpp
```

详细分发流程见 [镜像分发指南.md](镜像分发指南.md)。

## 故障排除

| 问题 | 原因 | 解决 |
|------|------|------|
| "Models not initialized" | 使用了 `--device cpu` | 改用 `--device cuda` |
| "failed to stat CDI host device" | CDI 方式不可用 | 用 `start.sh`（已处理） |
| `ModuleNotFoundError: deepaw_cpp` | 缺少环境变量 | 用 `start.sh`（已处理） |
| `libtorch.so: cannot open` | LD_LIBRARY_PATH 未设置 | 用 `start.sh`（已处理） |
| nvidia-smi 容器内不可用 | NVIDIA 库未挂载 | 用 `start.sh`（已处理） |
| `.so` 文件找不到 | 驱动版本升级了 | `start.sh` 自动检测，一般无需处理 |

## 文件说明

```
deepaw_cpp_docker/
├── start.sh               # ★ 一键启动脚本（推荐）
├── build.sh               # 构建镜像脚本
├── Containerfile           # GPU 镜像定义
├── welcome.sh              # 容器欢迎界面
├── deepaw_dist_v1_cpp/     # 分发包源文件
│   └── deepaw-cppv1.tar.gz  # 预构建镜像 tar 包 (6.1G)
├── output/                 # 推理输出目录
├── README.md               # 本文档
├── 镜像分发指南.md          # 镜像导出/传输/加载指南
└── archive/                # 归档文件（旧版脚本、构建日志、重复镜像包）
```

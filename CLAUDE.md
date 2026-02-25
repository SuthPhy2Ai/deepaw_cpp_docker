# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the Podman/Docker containerization layer for the DeePAW C++ inference engine. It packages the pre-built C++ encrypted model inference distribution (`deepaw_dist_v1_cpp/`) into a container image for portable deployment. The actual C++ source code lives in the parent project — this repo only handles container build, run, and distribution.

The container runs CHGCAR (VASP charge density) predictions from ASE databases using AES-256-GCM encrypted neural network models with decryption keys compiled into C++ shared libraries.

## Build and Run Commands

```bash
# Build the GPU container image
./build.sh
# or manually:
podman build -t deepaw-cpp:latest -f Containerfile .

# Load a pre-built image from tarball
podman load -i deepaw_dist_v1_cpp/deepaw-cppv1.tar.gz

# Run with the helper script (sets env vars automatically)
./run.sh --db tests/hfo2.db --id 1 --device cuda --output ./output
```

### Manual Container Run (GPU)

On this host (Rocky Linux 9.2, driver 525.60.13), CDI mode (`--device nvidia.com/gpu=all`) does not work. Must manually mount NVIDIA devices and libraries:

```bash
podman run --rm \
    --security-opt=label=disable \
    --device /dev/nvidia0 --device /dev/nvidiactl \
    --device /dev/nvidia-uvm --device /dev/nvidia-uvm-tools --device /dev/nvidia-modeset \
    -v /usr/lib64/libnvidia-ml.so.525.60.13:/usr/lib64/libnvidia-ml.so.525.60.13:ro \
    -v /usr/lib64/libcuda.so.525.60.13:/usr/lib64/libcuda.so.525.60.13:ro \
    -v /usr/lib64/libnvidia-ptxjitcompiler.so.525.60.13:/usr/lib64/libnvidia-ptxjitcompiler.so.525.60.13:ro \
    -e PYTHONPATH=/app/deepaw \
    -e LD_LIBRARY_PATH=/app/deepaw:/usr/local/lib/python3.12/dist-packages/torch/lib:/usr/lib64 \
    deepaw-cpp:latest \
    python predict_chgcar.py --db tests/hfo2.db --id 1 --device cuda
```

If the NVIDIA driver version changes, update all `525.60.13` references (check with `nvidia-smi`).

### Interactive Shell

```bash
podman run --rm -it \
    --security-opt=label=disable \
    --device /dev/nvidia0 --device /dev/nvidiactl \
    --device /dev/nvidia-uvm --device /dev/nvidia-uvm-tools --device /dev/nvidia-modeset \
    -v /usr/lib64/libnvidia-ml.so.525.60.13:/usr/lib64/libnvidia-ml.so.525.60.13:ro \
    -v /usr/lib64/libcuda.so.525.60.13:/usr/lib64/libcuda.so.525.60.13:ro \
    -v /usr/lib64/libnvidia-ptxjitcompiler.so.525.60.13:/usr/lib64/libnvidia-ptxjitcompiler.so.525.60.13:ro \
    -e PYTHONPATH=/app/deepaw \
    -e LD_LIBRARY_PATH=/app/deepaw:/usr/local/lib/python3.12/dist-packages/torch/lib:/usr/lib64 \
    deepaw-cpp:latest /bin/bash
```

## Architecture

### Container Structure (inside /app/)

```
/app/
├── predict_chgcar.py          # Main inference script (CLI entry point)
├── deepaw/
│   ├── __init__.py            # Python API: Model/SecureModel classes
│   ├── deepaw_cpp.cpython-312-x86_64-linux-gnu.so  # pybind11 bindings
│   ├── libdeepaw_core.so      # C++ core (contains compiled decryption key)
│   └── data/                  # Graph construction utilities (collate, KdTree)
├── models/
│   ├── f_nonlocal.enc         # Encrypted GNN model (~20MB)
│   └── f_local.enc            # Encrypted KAN correction model (~300KB)
└── tests/hfo2.db              # Built-in test data (HfO2)
```

### Inference Pipeline

`predict_chgcar.py` drives the full pipeline:
1. Loads crystal structure from ASE database
2. Generates 3D probe grid in fractional coordinates, converts to Cartesian
3. Splits probes into fixed batches of 1000 (pads last batch if needed)
4. For each batch: builds graph via `KdTreeGraphConstructor` → runs `SecureModel(batch)` → collects predictions
5. Writes VASP CHGCAR file via ASE's `VaspChargeDensity`

The `SecureModel.__call__` delegates to `InferenceEngine.predict_dual()` in C++, which runs F_nonlocal + F_local and returns combined predictions.

### Containerfile

- `Containerfile` — GPU version, based on `nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04`
- Installs Python 3.12 from deadsnakes PPA and pip-installs from `deepaw_dist_v1_cpp/requirements.txt`
- CPU Containerfile archived (encrypted models don't support CPU)

## Critical Constraints

- **CUDA only**: The encrypted model decryption is compiled for CUDA. Using `--device cpu` causes silent initialization failure.
- **Python 3.12 exact**: The `.so` bindings are compiled for cpython-312. Other versions won't load.
- **Environment variables required**: Container must have `PYTHONPATH=/app/deepaw` and `LD_LIBRARY_PATH` including `/app/deepaw` and torch lib path. The `start.sh` script handles this; raw `podman run` commands must set them explicitly.
- **Batch size = 1000**: The C++ engine expects exactly 1000 probe points per batch. `predict_chgcar.py` handles splitting/padding automatically.

## Key Files in This Repo

- `start.sh` — One-click launch script (auto-detects driver version, mounts GPU devices)
- `Containerfile` — GPU container image definition
- `build.sh` — Builds the podman image from `deepaw_dist_v1_cpp/`
- `welcome.sh` — ASCII art welcome screen shown on container bash login
- `deepaw_dist_v1_cpp/` — Pre-built distribution package (source of truth for container contents)
- `deepaw_dist_v1_cpp/deepaw-cppv1.tar.gz` — Pre-exported container image tarball
- `镜像分发指南.md` — Image distribution guide (save/load/transfer instructions)
- `archive/` — Archived files (old scripts, build logs, duplicate image tarballs)

## Image Distribution

```bash
# Export image
podman save deepaw-cpp:v1 | gzip > deepaw-cpp-v1.tar.gz

# Load on another machine
gunzip -c deepaw-cpp-v1.tar.gz | podman load

# Verify
podman images | grep deepaw-cpp
```

## Performance Reference

HfO2 test (id=1, 40x40x40 grid, 64000 points, 64 batches): ~27 seconds on RTX 4090.

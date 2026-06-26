#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# CUDA 검사 및 설정
echo "Checking CUDA availability..."

# Python을 통한 CUDA 검사
python_cuda_check() {
    python3 -c "
import torch
try:
    if torch.cuda.is_available():
        print('CUDA_AVAILABLE')
        exit(0)
    else:
        print('CUDA_NOT_AVAILABLE')
        exit(1)
except Exception as e:
    print(f'CUDA_ERROR: {e}')
    exit(2)
" 2>/dev/null
}

# CUDA 검사 실행
cuda_status=$(python_cuda_check)
case $? in
    0)
        echo "✅ CUDA is available and working (Python check)"
        export CUDA_VISIBLE_DEVICES=0
        export FORCE_CUDA=1
        ;;
    1)
        echo "❌ CUDA is not available (Python check)"
        echo "Error: CUDA is required but not available. Exiting..."
        exit 1
        ;;
    2)
        echo "❌ CUDA check failed (Python check)"
        echo "Error: CUDA initialization failed. Exiting..."
        exit 1
        ;;
esac

# 추가적인 nvidia-smi 검사
if command -v nvidia-smi &> /dev/null; then
    if nvidia-smi &> /dev/null; then
        echo "✅ NVIDIA driver working (nvidia-smi check)"
    else
        echo "❌ NVIDIA driver found but not working"
        echo "Error: NVIDIA driver is not working properly. Exiting..."
        exit 1
    fi
else
    echo "❌ NVIDIA driver not found"
    echo "Error: NVIDIA driver is required but not found. Exiting..."
    exit 1
fi

# CUDA 환경 변수 설정
echo "Using CUDA device: $CUDA_VISIBLE_DEVICES"

# Start ComfyUI in the background
# 참고: --highvram 는 쓰지 않음 — fp8 diffusion(~20GB)+텍스트인코더(~8GB)가
# ADA_24(24GB)를 초과해 OOM 위험. ComfyUI 기본 메모리 관리가 워밍업 후
# 모델을 상주시키므로 warm 요청은 이미 빠름.
echo "Starting ComfyUI in the background..."
python /ComfyUI/main.py --listen --use-sage-attention &

# Wait for ComfyUI to be ready
echo "Waiting for ComfyUI to be ready..."
max_wait=120  # 최대 2분 대기
wait_count=0
while [ $wait_count -lt $max_wait ]; do
    if curl -s http://127.0.0.1:8188/ > /dev/null 2>&1; then
        echo "ComfyUI is ready!"
        break
    fi
    echo "Waiting for ComfyUI... ($wait_count/$max_wait)"
    sleep 2
    wait_count=$((wait_count + 2))
done

if [ $wait_count -ge $max_wait ]; then
    echo "Error: ComfyUI failed to start within $max_wait seconds"
    exit 1
fi

# 모델 워밍업 — 첫 실제 요청에서 일어나던 콜드 모델 로딩을 부팅 시점으로 이동.
# FlashBoot/active worker와 함께 쓰면 첫 요청 지연이 크게 줄어듭니다. (실패해도 비치명적)
echo "Warming up models (preloading into VRAM)..."
python /warmup.py || echo "⚠️ Warmup skipped/failed (non-fatal)"

# Start the handler in the foreground
# 이 스크립트가 컨테이너의 메인 프로세스가 됩니다.
echo "Starting the handler..."
exec python handler.py
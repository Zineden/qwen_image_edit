# Use specific version of nvidia cuda image
FROM wlsdml1114/multitalk-base:1.7 as runtime

# ⚠️ 빌드 캐시 주의:
# 아래 base/apt/pip/git/모델 wget 레이어들은 upstream(wlsdml1114) 원본과
# "바이트 단위로 동일"하게 유지한다. 그래야 RunPod 빌드 캐시가 원본 릴리스에서
# 만들어 둔 무거운 레이어(베이스 + 28GB 모델)를 재사용할 수 있어, 30분 빌드
# 제한 안에 들어온다. 우리 변경(boto3, 핸들러 등)은 모델 다운로드 "이후"에만
# 추가해 새로 export 되는 레이어를 최소화한다.

# wget 설치 (URL 다운로드를 위해)
RUN apt-get update && apt-get install -y wget && rm -rf /var/lib/apt/lists/*

RUN pip install -U "huggingface_hub[hf_transfer]"
RUN pip install runpod websocket-client librosa

# Set working directory
WORKDIR /

RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    pip install --no-cache-dir -r requirements.txt

RUN cd /ComfyUI/custom_nodes/ && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    cd ComfyUI-Manager && \
    pip install --no-cache-dir -r requirements.txt

RUN cd /ComfyUI/custom_nodes/ && \
    git clone https://github.com/kijai/ComfyUI-KJNodes && \
    cd ComfyUI-KJNodes && \
    pip install --no-cache-dir -r requirements.txt

# Download models
RUN wget -q https://huggingface.co/Comfy-Org/Qwen-Image-Edit_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_edit_2511_fp8mixed.safetensors -O /ComfyUI/models/diffusion_models/qwen_image_edit_2511_fp8mixed.safetensors
RUN wget -q https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning/resolve/main/Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors -O /ComfyUI/models/loras/Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors
RUN wget -q https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors -O /ComfyUI/models/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors 
RUN wget -q https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors -O /ComfyUI/models/vae/qwen_image_vae.safetensors

# ↓↓↓ 여기서부터 우리 변경분 (모델 레이어 이후 = 작은 신규 레이어만 export) ↓↓↓
# boto3: 결과 이미지를 R2(S3 호환)에 직접 업로드하기 위함
RUN pip install --no-cache-dir boto3

COPY . .
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]

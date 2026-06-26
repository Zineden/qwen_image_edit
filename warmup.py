"""부팅 시 모델 워밍업.

ComfyUI가 준비된 뒤 더미 이미지로 1-image 워크플로우를 한 번 실행해
diffusion / text-encoder / VAE 를 VRAM에 미리 로드한다. 이렇게 하면
첫 실제 요청에서 발생하던 콜드 모델 로딩 지연이 사라진다.
실패는 비치명적 — 부팅을 막지 않는다.
"""
import json
import os
import time
import urllib.request

SERVER = os.getenv("SERVER_ADDRESS", "127.0.0.1") + ":8188"
WF = "/workflow/qwen_image_edit_1_1image.json"


def main():
    from PIL import Image

    dummy = "/tmp/_warmup.png"
    Image.new("RGB", (512, 512), (200, 200, 200)).save(dummy)

    wf = json.load(open(WF))
    wf["78"]["inputs"]["image"] = dummy          # LoadImage
    wf["111"]["inputs"]["prompt"] = "warmup"     # prompt

    data = json.dumps({"prompt": wf, "client_id": "warmup"}).encode()
    req = urllib.request.Request(f"http://{SERVER}/prompt", data=data)
    pid = json.loads(urllib.request.urlopen(req, timeout=30).read())["prompt_id"]
    print(f"warmup queued: {pid}", flush=True)

    for _ in range(180):  # 최대 ~6분
        time.sleep(2)
        try:
            h = json.loads(urllib.request.urlopen(
                f"http://{SERVER}/history/{pid}", timeout=10).read())
        except Exception:
            continue
        entry = h.get(pid)
        if entry and (entry.get("outputs") or
                      entry.get("status", {}).get("completed")):
            print("warmup complete", flush=True)
            return
    print("warmup timed out (non-fatal)", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"warmup error (non-fatal): {e}", flush=True)

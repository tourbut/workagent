#!/usr/bin/env python3
import os
import sys
import argparse
import json
import urllib.request
import urllib.error
import mimetypes
import uuid

def encode_multipart_formdata(fields, files):
    boundary = f"----HermesFormBoundary{uuid.uuid4().hex}"
    body = []
    
    # Add text fields
    for key, value in fields.items():
        body.append(f"--{boundary}".encode("utf-8"))
        body.append(f'Content-Disposition: form-data; name="{key}"'.encode("utf-8"))
        body.append(b"")
        body.append(str(value).encode("utf-8"))
        
    # Add files
    for key, (filename, file_bytes) in files.items():
        mime_type = mimetypes.guess_type(filename)[0] or "application/octet-stream"
        body.append(f"--{boundary}".encode("utf-8"))
        body.append(f'Content-Disposition: form-data; name="{key}"; filename="{filename}"'.encode("utf-8"))
        body.append(f"Content-Type: {mime_type}".encode("utf-8"))
        body.append(b"")
        body.append(file_bytes)
        
    body.append(f"--{boundary}--".encode("utf-8"))
    body.append(b"")
    
    content_type = f"multipart/form-data; boundary={boundary}"
    return content_type, b"\r\n".join(body)

def load_fallback_env():
    # Target files to look for configuration
    paths = [
        "/opt/data/.env",
        "/opt/hermes/.env",
        ".env",
        "../.env",
        "../../.env"
    ]
    env_vars = {}
    for p in paths:
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        # Skip comment and empty lines
                        if line and not line.startswith("#") and "=" in line:
                            parts = line.split("=", 1)
                            if len(parts) == 2:
                                k = parts[0].strip()
                                v = parts[1].strip().strip("'").strip('"')
                                env_vars[k] = v
            except Exception:
                pass
    return env_vars

def upload_report(file_path, channel_id=None, root_id=None, message=None):
    # 1. 환경변수 확인 (우선순위: 실제 프로세스 환경변수 -> .env 폴백 파일들)
    mm_url = os.getenv("MATTERMOST_URL") or os.getenv("HERMES_MATTERMOST_URL")
    mm_token = os.getenv("MATTERMOST_TOKEN") or os.getenv("HERMES_MATTERMOST_TOKEN")
    
    if not mm_url or not mm_token:
        print("[*] 시스템 환경변수 누락 감지. .env 파일로부터 설정을 로드합니다...")
        fallback_vars = load_fallback_env()
        if not mm_url:
            mm_url = fallback_vars.get("MATTERMOST_URL") or fallback_vars.get("HERMES_MATTERMOST_URL")
        if not mm_token:
            mm_token = fallback_vars.get("MATTERMOST_TOKEN") or fallback_vars.get("HERMES_MATTERMOST_TOKEN")
            
    if not mm_url:
        print("에러: MATTERMOST_URL 환경변수가 설정되지 않았습니다.", file=sys.stderr)
        return False
    if not mm_token:
        print("에러: MATTERMOST_TOKEN 환경변수가 설정되지 않았습니다.", file=sys.stderr)
        return False
        
    mm_url = mm_url.rstrip("/")
    
    # 2. 채널 ID 기본값 설정
    if not channel_id:
        channel_id = os.getenv("MATTERMOST_HOME_CHANNEL")
    if not channel_id:
        # allowed channels에서 첫 번째 값 시도
        allowed = os.getenv("MATTERMOST_ALLOWED_CHANNELS")
        if allowed:
            channel_id = allowed.split(",")[0].strip()
            
    if not channel_id:
        print("에러: 대화 채널 ID를 식별할 수 없습니다. --channel 인자 또는 MATTERMOST_HOME_CHANNEL 환경변수를 제공해야 합니다.", file=sys.stderr)
        return False
        
    # 3. 파일 검증
    if not os.path.exists(file_path):
        print(f"에러: 파일이 존재하지 않습니다: {file_path}", file=sys.stderr)
        return False

    # 4. 파일 업로드 API 요청 (POST /api/v4/files)
    upload_url = f"{mm_url}/api/v4/files"
    
    print(f"[*] 파일을 업로드 중입니다: {file_path}")
    try:
        with open(file_path, "rb") as f:
            file_bytes = f.read()
            
        fields = {"channel_id": channel_id}
        files = {"files": (os.path.basename(file_path), file_bytes)}
        
        content_type, body_bytes = encode_multipart_formdata(fields, files)
        
        req = urllib.request.Request(
            upload_url,
            data=body_bytes,
            headers={
                "Authorization": f"Bearer {mm_token}",
                "Content-Type": content_type
            },
            method="POST"
        )
        
        try:
            with urllib.request.urlopen(req) as response:
                res_body = response.read().decode("utf-8")
                res_json = json.loads(res_body)
        except urllib.error.HTTPError as he:
            err_body = he.read().decode("utf-8")
            print(f"에러: 파일 업로드에 실패했습니다. (HTTP {he.code}) - {err_body}", file=sys.stderr)
            return False
            
        file_infos = res_json.get("file_infos", [])
        if not file_infos:
            print("에러: 파일 업로드 응답에 file_infos가 비어있습니다.", file=sys.stderr)
            return False
            
        file_id = file_infos[0]["id"]
        print(f"[+] 파일 업로드 성공! File ID: {file_id}")
        
    except Exception as e:
        print(f"에러: 파일 업로드 중 예외 발생: {str(e)}", file=sys.stderr)
        return False

    # 5. 포스트 작성 API 요청 (POST /api/v4/posts)
    post_url = f"{mm_url}/api/v4/posts"
    
    if not message:
        message = "📋 **의료진 AX 워크플로우 분석 결과 보고서**가 생성되었습니다. 아래 첨부파일을 확인해주시기 바랍니다."
        
    post_data = {
        "channel_id": channel_id,
        "message": message,
        "file_ids": [file_id]
    }
    
    if root_id:
        post_data["root_id"] = root_id

    print(f"[*] 포스트를 생성합니다. (Channel: {channel_id}, Root Thread: {root_id or '없음'})")
    try:
        req_post = urllib.request.Request(
            post_url,
            data=json.dumps(post_data).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {mm_token}",
                "Content-Type": "application/json"
            },
            method="POST"
        )
        
        try:
            with urllib.request.urlopen(req_post) as response:
                print("[+] 성공적으로 Mattermost에 보고서 파일과 포스트를 업로드했습니다!")
                return True
        except urllib.error.HTTPError as he:
            err_body = he.read().decode("utf-8")
            print(f"에러: 포스트 생성에 실패했습니다. (HTTP {he.code}) - {err_body}", file=sys.stderr)
            return False
            
    except Exception as e:
        print(f"에러: 포스트 전송 중 예외 발생: {str(e)}", file=sys.stderr)
        return False

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="의료진 AX 인터뷰 보고서 마크다운을 Mattermost에 파일로 업로드하고 포스트합니다.")
    parser.add_argument("--file", required=True, help="업로드할 마크다운 파일 경로")
    parser.add_argument("--channel", help="업로드할 채널 ID (생략 시 기본 환경변수 사용)")
    parser.add_argument("--root", help="스레드 답글로 전송할 경우 상위 포스트 ID (Root ID)")
    parser.add_argument("--message", help="업로드 메시지 본문")
    
    args = parser.parse_args()
    
    success = upload_report(
        file_path=args.file,
        channel_id=args.channel,
        root_id=args.root,
        message=args.message
    )
    sys.exit(0 if success else 1)

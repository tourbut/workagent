#!/usr/bin/env python3
import os
import sys
import argparse
import requests

def upload_report(file_path, channel_id=None, root_id=None, message=None):
    # 1. 환경변수 확인
    mm_url = os.getenv("MATTERMOST_URL")
    mm_token = os.getenv("MATTERMOST_TOKEN")
    
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
    headers = {"Authorization": f"Bearer {mm_token}"}
    
    print(f"[*] 파일을 업로드 중입니다: {file_path}")
    try:
        with open(file_path, "rb") as f:
            files = {
                "files": (os.path.basename(file_path), f)
            }
            data = {
                "channel_id": channel_id
            }
            response = requests.post(upload_url, headers=headers, files=files, data=data)
            
        if response.status_code != 201:
            print(f"에러: 파일 업로드에 실패했습니다. (HTTP {response.status_code}) - {response.text}", file=sys.stderr)
            return False
            
        res_json = response.json()
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
        response = requests.post(post_url, headers=headers, json=post_data)
        if response.status_code != 201:
            print(f"에러: 포스트 생성에 실패했습니다. (HTTP {response.status_code}) - {response.text}", file=sys.stderr)
            return False
            
        print("[+] 성공적으로 Mattermost에 보고서 파일과 포스트를 업로드했습니다!")
        return True
        
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

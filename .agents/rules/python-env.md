---
trigger: always_on
description: 이 저장소의 Python 실행 환경 (uv 기반) 및 필수 명령어
---

# Python 실행 환경

이 저장소는 **uv** 기반 가상환경을 사용합니다. Python 코드를 실행하거나 의존성을 추가할 때 아래 규칙을 따릅니다.

## venv 경로
`.venv/` (프로젝트 루트)

## 실행 명령
```bash
uv run <실행파일>
```
파이썬 스크립트 직접 실행 시 `python xxx.py`가 아니라 `uv run xxx.py`를 사용합니다.

## 라이브러리 설치
```bash
uv add <패키지명>
```
`pip install`을 직접 호출하지 않습니다.

## 동기화
```bash
uv sync
```
`pyproject.toml` / `uv.lock` 업데이트 후 환경을 맞출 때 사용합니다.

## 주의
- `python` 또는 `pip`를 직접 호출하지 말고 반드시 `uv`를 경유합니다.
- venv가 활성화되어 있지 않아도 `uv run`은 정상 동작합니다.

## 외부 스킬(third-party) 문서 처리

`.agents/skills/` 하위에 들여온 외부 스킬(예: `markitdown`, `xlsx`, `pdf`, `gh-cli`, `skill-creator`, `mcp-builder`, `github-actions-writer`, `digital-brain-skill` 등)의 `SKILL.md`는 글로벌 Python 환경을 가정하여 `python`/`python3`/`pip` 직접 호출 형태로 작성되어 있는 경우가 많습니다. 업스트림 동기화 비용을 줄이기 위해 **원문은 그대로 보존**하고, 에이전트가 **런타임에 다음 규칙으로 치환**해 실행합니다.

| 원문 | 치환 |
|---|---|
| `python xxx.py ...` / `python3 xxx.py ...` | `uv run xxx.py ...` |
| `python -m <모듈> ...` / `python3 -m <모듈> ...` | `uv run python -m <모듈> ...` |
| `pip install <pkg>` / `pip3 install <pkg>` | `uv add <pkg>` |
| `pip install -e <path>` | `uv pip install -e <path>` (편집 가능 설치는 `uv add` 미지원) |
| `pip install -r requirements.txt` | `uv pip install -r requirements.txt` |

치환 후 모듈을 찾을 수 없는 오류가 발생하면 `uv add` 또는 `uv sync`로 의존성을 먼저 맞춥니다. 외부 스킬의 SKILL.md 자체를 수정하지는 않으며, 만약 수정이 필요한 경우(예: 하드코딩된 OS 절대경로)는 별도 커밋으로 분리합니다.

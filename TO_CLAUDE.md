# To Claude / Fable

갱신: 2026-09-14 UTC

## 현재 작업 선택

| 작업 | 담당 범위 | 실행 지시 | 상태 |
|---|---|---|---|
| **HWR-ENV-001** | 풀 외 업로드 모델 9종 경량화·재질·실제 마을 적용 | [TO_CLAUDE_ENVIRONMENT.md](TO_CLAUDE_ENVIRONMENT.md) | 새 작업, Fable 로컬 세션 |
| **HWR-GRASS-001** | 풀밭 경량화·타일·바람·반복 배치 검토 | [TO_CLAUDE_GRASS.md](TO_CLAUDE_GRASS.md) | 별도 담당이 진행 중, 보존 |

사용자가 맡긴 작업만 진행한다. 풀 담당이 최신 main을 반영했다고 해서 환경 9종으로 작업을 바꾸지 않는다. 환경 담당은 풀을 다시 제작하지 않는다. 두 세션은 **서로 다른 worktree/clone 경로**를 사용한다.

## 시작할 때 확인

- `CLAUDE.md`, `reports/README.md`, 지정된 실행 지시를 읽는다.
- 게임 구현은 이제 main에 병합됐다. 확인 기준 `22a21cf974479cb6fc213fe9c0120e31520db6d1` (PR #2 병합). 최신 main과 사용자 변경을 보존한다.
- 원본 총 10개 중 풀은 별도 작업, 이번 환경은 9개다. [제작 목록](docs/ENVIRONMENT_ASSET_KIT.md), [원본 경로/해시](docs/ENVIRONMENT_SOURCE_INVENTORY.json)를 확인한다.
- 풀 브랜치 `claude/hwr-grass-001`의 `5544f88aa4c17a288f655fffd348ea19e90dce42`에 환경 원본 5개가 추가돼 있다. 환경 담당은 필요한 **원본 경로만** 가져오고 풀 셰이더·베이크 도구·중간 파일을 함께 가져오지 않는다. 상세 절차는 환경 지시서에 있다.
- 로컬 Godot의 실제 renderer/GPU를 확인하고 실제 마을 검수와 성능을 기록한다. 검증하지 않은 항목은 완료라고 보고하지 않는다.
- 전투·경제·저장·정령·마을 크기/카메라를 새 에셋 때문에 다시 설계하지 않는다.

## 이전 작업

[HWR-006 지시](handoffs/2026-09-13_083537_KST_HWR-006_SPIRIT_VILLAGE.md)와 [완료 보고](reports/HWR-006.md)는 기존 구현의 참고 자료다. 과거의 “구현 전” 문구를 이유로 전체 재작업하지 않는다. [스토리](TO_CLAUDE_STORY.md)는 보류 상태다.

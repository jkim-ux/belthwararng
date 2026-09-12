# 벨트스크롤 게임 — 기획과 개발 전달 문서

현재는 **흰 오목눈이 바람 정령의 마을**을 디자인하고 있다. 정령이 직접 이동해 바람으로 농사하며, 사용자가 농장과 집을 놓는 모습을 낮은 측면 시점으로 보여주는 것이 목표다.

## 현재 작업

**[HWR-006](handoffs/2026-09-13_083537_KST_HWR-006_SPIRIT_VILLAGE.md)**: 마을 시점을 벨트스크롤로 통일하고, NPC·농장을 단순 카툰 3D로 표현한다. A 잎사귀 텃밭을 구현 시작용 기본안으로 사용한다. [A/B/C 아트 방향](docs/SPIRIT_VILLAGE_ART.md)을 함께 읽는다.

사용자가 보고한 005 건물 설치 불가의 [R1 수정](handoffs/2026-09-13_081833_KST_HWR-005_R1_PLACEMENT_INPUT.md)도 이번에 실제 입력으로 검증한다. **006은 지시 발행 상태이며 구현 완료를 뜻하지 않는다.**

스토리 집필과 주인공 디자인은 보류했다. 기존 전투·방 던전·난도·8스킬·캠페인·동료·저장은 이어서 사용한다. 기존 작업명/프로젝트 ID는 바꾸지 않는다.

## 전달 경로

| 문서 | 역할 |
| --- | --- |
| [TO_CLAUDE.md](TO_CLAUDE.md) | 항상 읽을 최신 구현 지시 |
| [HWR-006](handoffs/2026-09-13_083537_KST_HWR-006_SPIRIT_VILLAGE.md) | 시점·3D 표시·좌표·입력·정령 작업·검수 |
| [SPIRIT_VILLAGE_ART](docs/SPIRIT_VILLAGE_ART.md) | NPC·농장 3개 콘셉트와 제작 목록 |
| [GAME_DESIGN](docs/GAME_DESIGN.md) | 현재 변경 안내와 이전 전체 기획 |
| [VILLAGE_BUILDING](docs/VILLAGE_BUILDING.md) | 005의 자원·배치·관개·저장 기반 |
| [DIFFICULTY_AND_SKILLS](docs/DIFFICULTY_AND_SKILLS.md) | 004 전투·강인병·8스킬 |
| [DUNGEON_COMBAT](docs/DUNGEON_COMBAT.md) | 방·웨이브·원거리 적·화염·보스 |
| [COMBAT_FEEL](docs/COMBAT_FEEL.md) | 전투 모멘텀과 조작감 |
| [CAMPAIGN_SYSTEMS](docs/CAMPAIGN_SYSTEMS.md) | 기존 마을·경제·동료·저장 |
| [TO_CLAUDE_STORY.md](TO_CLAUDE_STORY.md) | 스토리 보류 상태와 이전 지시 기록 |
| [CLAUDE.md](CLAUDE.md) | 개발 공통 규칙 |
| [reports/README.md](reports/README.md) | 완료 보고 형식 |
| [game/README.md](game/README.md) | 게임 실행과 검증 안내 |

작성 시 main 2506243에 004가 병합되어 있고, 005 구현은 [PR #2](https://github.com/jkim-ux/belthwararng/pull/2)의 [claude/magical-bohr-2eljuj](https://github.com/jkim-ux/belthwararng/tree/claude/magical-bohr-2eljuj)에 있다. 작업 시작 시 최신 상태를 확인하고 005 구현에서 이어 간다.

# 사무라이 점령전 기획과 개발 전달 문서

사무라이가 첫 마을에서 반격을 시작해 점령지를 되찾는 벨트스크롤 액션 게임이다. 전체 5챕터, 챕터마다 전투 동료 1명 해금이 목표다. 주민은 농사·보급·복구를 맡는다.

## 현재 작업
현재 기획은 **v0.4**, 구현 지시는 **HWR-003**이다. 완료된 HWR-002의 전투·마을·동료·저장을 이어서 확장한다.
이번 범위는 1챕터 각 거점의 방 던전 전환, 일반 방2웨이브, 적 궁수/화염 투척병, 우측 상단 미니맵, 보물방, 보스 처치 클리어다.

| 파일 | 역할 |
| --- | --- |
| [TO_CLAUDE.md](TO_CLAUDE.md) | 게임 구현 지시의 고정 진입점 |
| [TO_CLAUDE_STORY.md](TO_CLAUDE_STORY.md) | 스토리 집필 HWR-STORY-001 |
| [docs/story/STORY_BRIEF.md](docs/story/STORY_BRIEF.md) | 짧은 스토리 개요와 5챕터 뼈대 |
| [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md) | 세계·5챕터·전체 범위 |
| [docs/DUNGEON_COMBAT.md](docs/DUNGEON_COMBAT.md) | 방 연결·웨이브·신규 적·화염·미니맵·상자 |
| [docs/COMBAT_FEEL.md](docs/COMBAT_FEEL.md) | 모멘텀 수치·규칙·비교 검증 |
| [docs/CAMPAIGN_SYSTEMS.md](docs/CAMPAIGN_SYSTEMS.md) | 마을·경제·동료·보상·저장 |
| [CLAUDE.md](CLAUDE.md) | 개발 공통 진행 규칙 |
| [reports/README.md](reports/README.md) | 완료 보고 형식 |

## 기존 구현과 실행
확인 당시 HWR-001/002 코드는 [claude/upbeat-mayer-r3t54f 브랜치](https://github.com/jkim-ux/belthwararng/tree/claude/upbeat-mayer-r3t54f/game)에 있고 [게임 실행 안내](https://github.com/jkim-ux/belthwararng/blob/claude/upbeat-mayer-r3t54f/game/README.md)를 제공한다. [초안 PR #1](https://github.com/jkim-ux/belthwararng/pull/1)은 검토 시점에 미병합이다.
main에 game/가 아직 없다고 게임을 새로 작성하지 않는다. 실제 최신 구현/브랜치/보고를 확인하고 이어서 작업한다. 구현이 병합되면 기존 game/README.md 실행 안내를 유지한다.

## 전달 방식
기획 담당은 최신 코드와 결과 보고를 확인하고 날짜·한국시간·수정 번호가 있는 지시를 발행한다. 개발 담당은 사용자 변경을 보존하면서 원격 기획을 반영하고 현재 지시를 구현한다. 사용자는 플레이로 조작감과 재미를 판단한다.
이전 기획은 docs/archive/, 이전 지시는 handoffs/에 남긴다. 완료 보고는 reports/HWR-002.md처럼 같은 작업 번호를 쓰되 적용 수정 번호를 기록한다. 날짜만 비교하지 말고 TO_CLAUDE.md의 링크를 따른다.
문서 게시가 개발 도구를 자동으로 실행하지는 않는다. Claude에는 'main의 최신 TO_CLAUDE.md를 읽고 HWR-003을 기존 구현에 이어서 진행해'라고 전달하면 된다.

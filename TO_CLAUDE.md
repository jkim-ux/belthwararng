# To Claude

- 현재 작업: **HWR-004**
- 작성: 2026-09-12 20:24:34 KST / 2026-09-12T11:24:34Z
- 목표: 적 피해2배 · 강인병 · 패턴 보완 · 액티브8개 완성
- 기획: [GAME_DESIGN v0.5](docs/GAME_DESIGN.md)
- 실행 지시: [HWR-004](handoffs/2026-09-12_202434_KST_HWR-004_DIFFICULTY_SKILLS.md)
- 상세 규칙: [DIFFICULTY_AND_SKILLS](docs/DIFFICULTY_AND_SKILLS.md)
- 완료 보고: reports/HWR-004.md
- 상태: 지시 발행 / 구현 결과 미확인

HWR-003의 기존 전투·방·마을·동료·저장을 이어서 확장한다. 확인한 코드 브랜치는 claude/upbeat-mayer-r3t54f, 커밋bf014527, PR #1이다. 실제 최신 변경/보고를 우선하고 처음부터 만들지 않는다.

적 피해는 근접20/화살16/보스24/불6으로 올린다. 첫 농촌 battle_1의 두 웨이브는 기존 경직 반응을 유지하고 강인병은 battle_2부터 교체 배치한다. 강인병은 맞아도 공격이 진행되며 Q로만1초 자세를 무너뜨릴 수 있다.

A/S를 보존하고 D/F/Q/W/E/R을 실제 구현해8개를 완성한다. 새 스킬과 난도 변경을 같은 조건에서 비교하고 관련 회귀를 확인한다. [스토리 집필](TO_CLAUDE_STORY.md)은 별도이며 이번에 다시 실행하지 않는다.

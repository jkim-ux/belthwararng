# HWR-006 후속: 마을 바로 테스트

시작 화면에 **마을 바로 테스트 (전투 없이 · 별도 저장)** 버튼을 추가했다. `--village-test`로도 바로 들어갈 수 있다.

- 첫 농촌과 정령 3명, 군자금 1000·목재 300·석재 300·식량 100 및 기존 첫 마을 물자를 준비한다.
- 일반 저장 경로 뒤에 `.village_test`를 붙인 별도 슬롯을 사용한다. 일반 캠페인 상태와 저장 파일은 유지한다.
- 다시 들어가면 배치·작업·남은 자원을 불러온다. 초기 물자는 재지급하지 않는다.
- 테스트 종료 시 시작 화면으로 돌아간다. 일반 캠페인의 마을 해방 조건은 그대로다.

Godot 4.7.2에서 실제 Viewport 버튼 클릭·저장 격리·재입장·손상 저장 처리를 28개 검사, CLI 진입 3개 검사, 기존 V15 마을 화면 회귀 20개 검사를 통과했다. 실패 0.

```sh
godot --headless --path game -s tests/run_village_entry_tests.gd
godot --headless --path game -s tests/run_village_entry_tests.gd -- --village-test --save=user://test_saves/hwr006_village_cli.json --check-cli
godot --headless --path game -s tests/run_village_tests.gd -- --only=v15
```

별도로 제작한 정령·농장 GLB 14개와 정령 동작 6개는 사용자에게 독립 `spirit_farm_v1.zip`으로 전달한다. 이 커밋은 마을 테스트 진입 변경만 포함하며 새 GLB의 실제 마을 연결은 포함하지 않는다. 기존 005/006 구현 브랜치에 추가하고 PR #2를 병합하지 않는다.

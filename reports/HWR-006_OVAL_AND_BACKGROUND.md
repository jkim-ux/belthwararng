# HWR-006 후속: 오목눈이 비율과 농장 배경 v1.1

- 상태: 완료. 모델 비율·미리보기 색상 수정, 기존 게임 마을의 정령 비율·배경 수정.
- 시작: 2026-09-13T02:51Z. 완료: 2026-09-13T03:05:58+00:00 / 2026-09-13 12:05 KST.
- 기준: `claude/magical-bohr-2eljuj`의 `0d5e1b67ab74b772339fb474589f9c03fc8ff338`. 별도 작업 브랜치 `codex/spirit-oval-and-background`.
- 읽은 지침: `CLAUDE.md`, `TO_CLAUDE.md`, `reports/README.md`. 사용자가 새로 제공한 사진·굿즈 참고와 배경 변경 요청을 적용했다.

## 수정

1. GLB 정령의 몸통 폭 1.12→1.00m, 높이 1.16→1.28m. 위가 약간 좁고 배는 도톰한 세로 달걀형. 짧은 솜털·꽃·긴 꼬리를 유지했다. 눈·부리·날개·꽃 부착점과 6개 애니메이션의 몸 중심 높이를 함께 조정했다.
2. 독립 모델 미리보기 `Farm` 화면: 배경 `#87A6AB`, 바닥 `#719489`. 조명 총량을 줄이고 글자색도 어둡게 바꿔 흰 정령·밝은 건물이 배경과 구분되도록 했다.
3. 실제 게임 `VillageStage3D`: 같은 청록 배경, 세이지 잔디 `#759782`, 차분한 흙길 `#BAA57E`, 환경광 0.75→0.6.
4. 실제 게임 `SpiritActor3D`: 세로 타원 비율, 눈·부리·발·머리 장식 위치 조정. 기존 메시를 사용하며 새로운 GLB의 마을 연결은 이번 범위에 포함하지 않는다.

## 참고

- 사용자 첨부 사진: 서로 다른 자세의 흰 오목눈이 두 마리.
- [사용자가 지정한 굿즈](https://tumblbug.com/cutebird11/community/review): 실제 프로젝트 커버의 캐릭터를 확인. 도톰한 가슴·작은 얼굴·뒤로 이어지는 꼬리의 비율 참고.
- [사진 작가의 오목눈이 촬영 소개](https://ameblo.jp/ajtakasaki1113/entry-12729863301.html): 고개를 기울인 정면 사진 확인.
- [NHK Culture 온라인 강좌 소개의 사진](https://gamepress.jp/archives/58150): 나뭇가지에 붙은 세로형 자세 사진 확인.

외부 이미지는 조사용으로만 확인했으며 GLB/ZIP 안에 넣지 않았다.

## 검증 및 전달

- Godot `4.7.2.stable.official.ed1daf0bf`, Linux headless.
- GLB 14개 Khronos Validator 오류 0·경고 0.
- Godot 가져오기, 정령 6개 동작·물레 회전·미리보기 장면 실행 통과.
- 기존 `test_v16_real_viewport_input_places_building`: 29개 검사 통과, 실패 0.
- 기존 `test_v18_spirit_states_wander_and_effects`: 결과: 통과 16, 실패 0.
- 실제 GLB를 ModernGL/EGL로 다시 읽어 정면·측면·후면, 농장 PNG, 동작 GIF를 렌더링하고 확인했다.
- `deliverables/spirit_farm_v1_1.zip`으로 독립 Godot 프로젝트와 모델·원본 소스를 전달한다. ZIP CRC 및 모델 SHA-256 확인.
- 실제 GUI 창의 Godot 캡처는 실행 환경에서 X 서버 소켓을 만들 수 없어 수행하지 못했다. 제공 PNG/GIF는 실제 GLB의 별도 OpenGL 렌더링이다. 전투·경제·저장 규칙은 변경하지 않았다.

게임 수정은 기존 006 작업 브랜치에 반영하며 PR은 병합하지 않는다. 모델은 별도 ZIP으로 전달한다. 최신 커밋은 이 보고서를 포함한 Git 기록에서 확인한다.

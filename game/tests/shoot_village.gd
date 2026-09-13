extends SceneTree
## HWR-005 화면 확인용 재현 스크립트였다. HWR-006 에서 마을 표시가 측면 카툰 3D 로 바뀌고 플레이어 직접 작업(E 누르기)이 사라져
## 같은 순서를 재현할 수 없으므로, 화면 캡처·영상은 tests/shoot_spirit_village.gd 를 사용한다. (HWR-005 캡처 reports/HWR-005_*.png 는 당시 결과)

func _initialize() -> void:
	print("HWR-006 부터는 tests/shoot_spirit_village.gd 를 실행한다 (xvfb-run -a -s \"-screen 0 1280x720x24\" godot --path game -s tests/shoot_spirit_village.gd)")
	quit()

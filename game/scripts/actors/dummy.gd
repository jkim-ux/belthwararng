class_name Dummy
extends EnemyBase
## 허수아비. 죽지 않고 누적 피해를 보여준다. 띄우기 규칙 확인을 위해 띄워질 수는 있지만 밀리지 않는다.

func _init() -> void:
	team = &"enemy"
	display_name = "허수아비"
	body_color = Color(0.75, 0.6, 0.35)
	knockback_enabled = false

func configure(p_tuning: CombatTuning, p_battle: Node, start: Vector2) -> void:
	setup(p_tuning, p_battle, start)
	max_hp = 0            # 0 = 무한 체력(사망 없음)
	hp = 0
	half_width = 20.0
	half_depth = 10.0
	body_height = 72.0
	facing = -1
	total_damage_taken = 0
	change_state(&"idle")

func _step_state() -> void:
	if _step_common_reactions():
		return
	# idle: 아무것도 하지 않는다

func _on_landed_from_launch() -> void:
	airborne_by_launch = false
	change_state(&"idle")

func _draw_body() -> void:
	super()
	# 기둥 표시
	var top := -height - body_height
	draw_rect(Rect2(-3.0, top + body_height, 6.0, 8.0), Color(0.4, 0.3, 0.15))

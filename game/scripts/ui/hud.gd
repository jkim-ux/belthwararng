class_name Hud
extends Control
## 전투 정보 표시: 체력, 구역, 스킬 8칸과 재사용 시간, 회피 대기, 조작 안내.
## 미구현 스킬은 회색으로 "미구현"이라 표시하고 사용 가능한 것처럼 보이지 않게 한다.

var battle: Battle

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	queue_redraw()

func _zone_text() -> String:
	if battle.mode == &"training":
		return "구역: 수련장 (프로필 비교)"
	return "구역: 거점 전투"

func _draw() -> void:
	if battle == null or battle.player == null:
		return
	var f := UiFont.FONT
	var p := battle.player
	# --- 상단: 체력과 구역
	draw_rect(Rect2(20, 16, 340, 26), Color(0, 0, 0, 0.55))
	var ratio := float(p.hp) / float(maxi(1, p.max_hp))
	draw_rect(Rect2(23, 19, 334 * ratio, 20), Color(0.35, 0.85, 0.4) if ratio > 0.3 else Color(0.9, 0.3, 0.3))
	draw_string(f, Vector2(28, 36), "%s  %d / %d" % [p.display_name, p.hp, p.max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	draw_string(f, Vector2(380, 36), _zone_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))
	if not p.alive:
		draw_string(f, Vector2(480, 200), "쓰러졌다 — F6 으로 초기화" if battle.mode == &"training" else "쓰러졌다", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 0.5, 0.5))
	if battle.paused:
		draw_string(f, Vector2(560, 300), "일시정지 (Esc)", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1))
	# --- 우상단: 조작 안내
	var help := [
		"방향키 이동   X 평타   C 점프(공중 평타 1회)   Space 회피",
		"A 돌진베기   S 올려베기   (D F Q W E R 미구현)",
	]
	if battle.mode == &"training":
		help.append("F1 개발 표시   F2 프로필 전환   F5 적 재생성   F6 초기화   F12 스크린샷   Esc 일시정지")
		var prof := battle.current_profile()
		help.append("프로필: %s — %s" % [prof.display_name, prof.description])
		if battle.profile_switch_message != "":
			help.append("(%s)" % battle.profile_switch_message)
	var y := 66.0
	for line in help:
		draw_string(f, Vector2(20, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.75))
		y += 18.0
	# --- 허수아비 누적 피해
	if battle.dummy != null and is_instance_valid(battle.dummy):
		draw_string(f, Vector2(900, 36), "허수아비 누적 피해: %d" % battle.dummy.total_damage_taken, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.9, 0.6))
	if battle.knockback_dummy != null and is_instance_valid(battle.knockback_dummy):
		draw_string(f, Vector2(900, 56), "밀림 표적 누적 피해: %d" % battle.knockback_dummy.total_damage_taken, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.95, 0.7))
	# --- 하단: 스킬 8칸
	var slot_w := 118.0
	var slot_h := 64.0
	var x0 := (1280.0 - (slot_w + 8.0) * 8.0) * 0.5
	var y0 := 720.0 - slot_h - 14.0
	var i := 0
	for sd in p.skill_set.skills:
		var r := Rect2(x0 + i * (slot_w + 8.0), y0, slot_w, slot_h)
		var implemented: bool = sd.implemented
		var bg := Color(0.12, 0.12, 0.16, 0.9) if implemented else Color(0.10, 0.10, 0.10, 0.75)
		draw_rect(r, bg)
		draw_rect(r, Color(0.85, 0.75, 0.45) if implemented else Color(0.35, 0.35, 0.35), false, 2.0)
		var name_col := Color.WHITE if implemented else Color(0.5, 0.5, 0.5)
		draw_string(f, r.position + Vector2(8, 22), sd.key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.9, 0.5) if implemented else Color(0.5, 0.5, 0.5))
		draw_string(f, r.position + Vector2(36, 22), sd.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, name_col)
		if not implemented:
			draw_string(f, r.position + Vector2(8, 50), "미구현 (후속 작업)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.55, 0.55))
		else:
			var cd: int = p.cooldown_for(sd)
			var total: int = sd.cooldown_ticks()
			if cd > 0:
				var frac := float(cd) / float(maxi(1, total))
				draw_rect(Rect2(r.position.x, r.position.y + r.size.y * (1.0 - frac), r.size.x, r.size.y * frac), Color(0, 0, 0, 0.55))
				draw_string(f, r.position + Vector2(8, 50), "%.1f 초" % (Ticks.to_ms(cd) / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.6, 0.6))
			else:
				draw_string(f, r.position + Vector2(8, 50), "준비됨  (재사용 %.0f초)" % (sd.cooldown_ms / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 1.0, 0.6))
		i += 1
	# --- 회피 대기
	var dr := Rect2(x0, y0 - 30, 200, 22)
	draw_rect(dr, Color(0, 0, 0, 0.5))
	if p.dodge_cooldown_ticks > 0:
		var frac := 1.0 - float(p.dodge_cooldown_ticks) / float(maxi(1, Ticks.from_ms(p.tuning.dodge_cooldown_ms)))
		draw_rect(Rect2(dr.position, Vector2(dr.size.x * frac, dr.size.y)), Color(0.5, 0.7, 1.0, 0.7))
		draw_string(f, dr.position + Vector2(6, 16), "회피 %.1f초" % (Ticks.to_ms(p.dodge_cooldown_ticks) / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	else:
		draw_rect(dr, Color(0.5, 0.7, 1.0, 0.7))
		draw_string(f, dr.position + Vector2(6, 16), "회피 준비됨", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	# 최근 사건
	var ly := y0 - 30.0
	for k in range(battle.event_log.size() - 1, -1, -1):
		draw_string(f, Vector2(1000, ly), battle.event_log[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
		ly -= 15.0

class_name DebugOverlay
extends Node2D
## 개발용 표시: 바닥 위치, 높이, 피격·공격 범위, 현재 행동, 대기시간, 틱 양자화 적용값.
## F1 로 켜고 끈다. 평소 플레이에서는 숨긴다.

var battle: Battle

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	if battle == null:
		return
	var f := UiFont.FONT
	for a in battle.all_actors():
		_draw_actor(a, f)
	_draw_panel(f)

func _draw_actor(a: BattleActor, f: Font) -> void:
	var fp := a.floor_pos
	# 바닥 위치 십자
	draw_line(fp + Vector2(-8, 0), fp + Vector2(8, 0), Color.WHITE, 1.5)
	draw_line(fp + Vector2(0, -8), fp + Vector2(0, 8), Color.WHITE, 1.5)
	# 피격 범위: 바닥 발자국(x·깊이)과 높이 상자
	var xr := a.hurt_x_range()
	var yr := a.hurt_y_range()
	var zr := a.hurt_z_range()
	var foot := Rect2(xr.x, yr.x, xr.y - xr.x, yr.y - yr.x)
	var hurt_col := Color(0.2, 1.0, 0.3, 0.9) if a.can_be_hit() else Color(0.6, 0.6, 0.6, 0.7)
	draw_rect(foot, hurt_col, false, 1.5)
	var body := Rect2(xr.x, fp.y - zr.y, xr.y - xr.x, zr.y - zr.x)
	draw_rect(body, Color(0.2, 0.9, 1.0, 0.8), false, 1.5)
	# 높이 선
	if a.height > 0.5:
		draw_line(fp, fp + Vector2(0, -a.height), Color(1, 1, 0.4), 2.0)
	# 공격 범위
	for hb in a.active_hitboxes:
		var hx := hb.world_x_range(fp)
		var hy := hb.world_y_range(fp)
		var hz := hb.world_z_range(a.height)
		draw_rect(Rect2(hx.x, hy.x, hx.y - hx.x, hy.y - hy.x), Color(1, 0.2, 0.2, 0.35))
		draw_rect(Rect2(hx.x, hy.x, hx.y - hx.x, hy.y - hy.x), Color(1, 0.1, 0.1, 0.9), false, 1.5)
		draw_rect(Rect2(hx.x, fp.y - hz.y, hx.y - hx.x, hz.y - hz.x), Color(1, 0.3, 0.9, 0.9), false, 1.5)
	# 텍스트
	var lines: Array[String] = []
	lines.append("%s  %s (%d틱)" % [a.display_name, a.state, a.state_ticks])
	lines.append("바닥 (%.0f, %.0f)  높이 %.0f" % [fp.x, fp.y, a.height])
	if a.max_hp > 0:
		lines.append("HP %d/%d" % [a.hp, a.max_hp])
	else:
		lines.append("누적 피해 %d" % a.total_damage_taken)
	if a.hitstop_ticks > 0:
		lines.append("타격 정지 %d틱" % a.hitstop_ticks)
	if a.invuln_ticks > 0:
		lines.append("무적 %d틱" % a.invuln_ticks)
	if a is EnemyBase and a.knockback_remaining > 0.0:
		lines.append("밀림 잔여 %.1f / %.0f px (%d/%d틱)" % [a.knockback_remaining, a.knockback_total, a.knockback_t, a.knockback_ticks])
	if a is Player:
		var p := a as Player
		if p.current_attack != null:
			lines.append("%s %s t=%d/%d" % [p.current_attack.display_name, p.attack_phase(), p.attack_t(), p.current_attack.total_ticks()])
			if p.current_attack.advance_px > 0.0:
				lines.append("전진 %.1f / %.0f px" % [p.attack_advance_done, p.current_attack.advance_px])
		if p.buffered_action != &"":
			lines.append("보관 입력 %s (%d/%d틱)" % [p.buffered_action, p.buffer_age, p.buffer_ticks()])
		lines.append("속도 (%.0f, %.0f)  방향 %d" % [p.velocity.x, p.velocity.y, p.facing])
	var ty := fp.y - a.height - a.body_height - 14.0 - lines.size() * 14.0
	for l in lines:
		draw_string(f, Vector2(fp.x - 60, ty), l, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.95))
		ty += 14.0

func _draw_panel(f: Font) -> void:
	var t := battle.tuning
	var p := battle.player
	var lines: Array[String] = []
	lines.append("개발 표시 (F1)  틱 %d  적중 %d" % [battle.tick, battle.hits_this_run])
	lines.append("--- 틱 양자화 (60/초, 1틱 = 16.7 ms) ---")
	lines.append(Ticks.describe("입력 보관", t.input_buffer_ms))
	lines.append(Ticks.describe("타격 정지 일반", t.hitstop_light_ms))
	lines.append(Ticks.describe("타격 정지 강공격", t.hitstop_strong_ms))
	lines.append(Ticks.describe("회피 이동", t.dodge_ms))
	lines.append(Ticks.describe("회피 무적", t.dodge_invuln_ms))
	lines.append(Ticks.describe("회피 재사용", t.dodge_cooldown_ms))
	lines.append("프로필 %s" % p.profile_id)
	for atk in p.light_attacks:
		lines.append("%s: 준비 %d 타격 %d 회복 %d 연결창 %d틱 전진 %.0f 밀림 %.0f/%d틱" % [atk.display_name, atk.startup_ticks(), atk.active_ticks(), atk.recovery_ticks(), atk.chain_window_ticks(), atk.advance_px, atk.knockback, atk.knockback_ticks()])
	for sd in p.skill_set.skills:
		if sd.implemented and sd.attack != null:
			var atk: AttackData = sd.attack
			lines.append("%s: 준비 %d 타격 %d 회복 %d 이동취소 %d틱 재사용 %d틱" % [sd.display_name, atk.startup_ticks(), atk.active_ticks(), atk.recovery_ticks(), atk.move_cancel_ticks(), sd.cooldown_ticks()])
	lines.append("--- %s ---" % p.display_name)
	lines.append("상태 %s  최근 %s" % [p.state, p.last_event])
	for sd in p.skill_set.skills:
		if sd.implemented:
			lines.append("%s 대기 %d틱" % [sd.display_name, p.cooldown_for(sd)])
	lines.append("회피 대기 %d틱" % p.dodge_cooldown_ticks)
	var w := 470.0
	var h := 16.0 * lines.size() + 12.0
	var origin := Vector2(1280.0 - w - 12.0, 130.0)
	draw_rect(Rect2(origin, Vector2(w, h)), Color(0, 0, 0, 0.6))
	var y := origin.y + 16.0
	for l in lines:
		draw_string(f, Vector2(origin.x + 8.0, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 1.0, 0.9))
		y += 16.0

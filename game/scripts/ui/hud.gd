class_name Hud
extends Control
## 전투 정보 표시: 체력, 구역, 스킬 8칸과 재사용 시간, 회피 대기, 조작 안내.
## 미구현 스킬은 회색으로 "미구현"이라 표시하고 사용 가능한 것처럼 보이지 않게 한다(HWR-004: 8개 모두 구현).
## HWR-004: 칸마다 짧은 역할 안내, 흘려받기 성공/실패, 일섬연무 타격 수, 강인병 무너짐/2연격/내려찍기, 보스 예고를 도형+문구로 표시한다.
## HWR-003: 우측 상단(여백 16px, 약 240×140)에 방 미니맵을 그린다. 남은 적/웨이브 문구는 상단 중앙으로 옮겼다.
## 미니맵은 던전의 같은 RoomDef 연결 데이터를 사용한다(격자 칸만 같고 문이 다른 상황이 없음).

const MINIMAP_W := 240.0
const MINIMAP_H := 140.0
const MINIMAP_MARGIN := 16.0

var battle: Battle

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	queue_redraw()

func _zone_text() -> String:
	if battle.mode == &"training":
		return "구역: 수련장 (프로필 비교)"
	if battle.encounter != null:
		var t := "구역: %s" % battle.encounter.display_name
		if battle.room != null:
			t += " — %s" % battle.room.display_name
		return t
	return "구역: 거점 전투"

## 현재 방의 목표 문구(미니맵과 별도 짧은 텍스트)
func _objective_text() -> String:
	if battle.room == null:
		return ""
	if battle.transition_ticks > 0:
		return "이동 중…"
	if battle.room.is_combat() and battle.doors_locked:
		var remaining := battle.required_alive_count()
		var total := battle.total_waves()
		var idx := mini(battle.wave_index, total)
		var txt := ""
		if battle.room.kind == &"boss":
			txt = "보스전 — 남은 적 %d" % remaining
		else:
			txt = "웨이브 %d/%d · 남은 적 %d" % [idx, total, remaining]
		if not battle.pending_spawns.is_empty():
			txt += " (출현 중 %d)" % battle.pending_spawns.size()
		elif remaining == 0 and battle.wave_index < total:
			txt += " · 다음 웨이브 준비"
		return txt
	if battle.room.kind == &"boss":
		return "보스 처치로 거점 클리어"
	if battle.room.kind == &"treasure":
		return "상자를 이미 열었다" if battle.chest_opened else "상자: 생존자 20% 회복 + 군자금 30 보류"
	if battle.is_room_cleared(battle.room.id):
		return "정리 완료 — 문이 열려 있다"
	return "문 앞에서 Enter 로 이동"

func _draw_campaign(f: Font) -> void:
	# 목표·적 등장 상태(상단 중앙)
	var txt := _objective_text()
	if txt != "":
		draw_string(f, Vector2(700, 36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.9, 0.6))
	if battle.pending_currency > 0:
		draw_string(f, Vector2(700, 56), "보류 군자금 %d (보스 승리 시 획득)" % battle.pending_currency, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.85, 0.5))
	if battle.room_message_ticks > 0 and battle.room_message != "":
		var w := f.get_string_size(battle.room_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_rect(Rect2(640 - w * 0.5 - 12, 150, w + 24, 30), Color(0, 0, 0, 0.5))
		draw_string(f, Vector2(640 - w * 0.5, 172), battle.room_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.95, 0.8))
	_draw_minimap(f)
	# 동료 체력
	if battle.companion != null and is_instance_valid(battle.companion):
		var c := battle.companion
		draw_rect(Rect2(20, 120, 220, 20), Color(0, 0, 0, 0.55))
		if c.alive:
			draw_rect(Rect2(22, 122, 216 * float(c.hp) / float(maxi(1, c.max_hp)), 16), Color(0.4, 0.9, 0.5))
			draw_string(f, Vector2(26, 135), "%s  %d / %d" % [c.display_name, c.hp, c.max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		else:
			draw_string(f, Vector2(26, 135), "%s  이탈 (다음 출정에서 회복)" % c.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.7, 0.7))
	# 대장 체력·예고
	for e in battle.enemies:
		if e is CaptainEnemy and is_instance_valid(e) and e.alive:
			draw_rect(Rect2(340, 100, 600, 22), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(342, 102, 596 * float(e.hp) / float(maxi(1, e.max_hp)), 18), Color(0.85, 0.2, 0.25))
			var pat := ""
			if e.state == &"telegraph":
				pat = "  예고: %s" % ("전방 베기 (E 가능)" if e.current_pattern == 0 else "직선 돌진 — 옆으로 피하라 (E 가능)")
			elif e.state == &"attack":
				pat = "  공격!"
			elif e.state == &"recover":
				pat = "  회복 — 공격 기회"
			draw_string(f, Vector2(348, 117), "%s  %d / %d%s" % [e.display_name, e.hp, e.max_hp, pat], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	_draw_brute_status(f)
	if battle.result_state != &"active":
		return
	if not battle.player.alive:
		draw_string(f, Vector2(480, 200), "쓰러졌다", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 0.5, 0.5))

## 강인병 상태(상단 중앙 아래): 무너짐 남은 시간 / 2연격 단계 / 내려찍기 예고. 색만이 아니라 문구·도형으로 구분한다.
func _draw_brute_status(f: Font) -> void:
	var y := 78.0
	for e in battle.enemies:
		if not (e is BruteEnemy) or not is_instance_valid(e) or not e.alive:
			continue
		var br := e as BruteEnemy
		var txt := ""
		var col := Color(0.9, 0.85, 1.0)
		if br.state == &"stagger":
			txt = "강인병 자세 무너짐 %.1f초 — 지금 공격" % (Ticks.to_ms(br.stagger_remaining_ticks()) / 1000.0)
			col = Color(0.6, 0.9, 1.0)
		elif br.state == &"telegraph" or br.state == &"attack":
			if br.current_pattern == 0:
				txt = "강인병 전방 2연격 %d/2 (E 로 한 타 방어 가능)" % mini(2, br.combo_stage() + 1)
			else:
				txt = "강인병 주변 내려찍기 — 범위 밖으로 (반격 불가)"
			col = Color(1.0, 0.75, 0.6)
		elif br.state == &"approach" or br.state == &"idle":
			txt = "강인병 접근 중 — 공격을 버틴다. Q 로 무너뜨리기"
		if txt != "":
			var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_rect(Rect2(700 - 6, y - 14, w + 12, 20), Color(0, 0, 0, 0.45))
			draw_string(f, Vector2(700, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
			y += 22.0

## 우측 상단 방 미니맵: 현재 방 테두리/점, 미방문 흐림, 방문, 정리 체크, 잠긴 문 자물쇠/막힌 선, 열린 문 연결선, 보스 B, 보물 ?/상자.
func _draw_minimap(f: Font) -> void:
	var d := battle.dungeon
	if d == null or battle.room == null:
		return
	var origin := Vector2(size.x - MINIMAP_MARGIN - MINIMAP_W, MINIMAP_MARGIN)
	draw_rect(Rect2(origin, Vector2(MINIMAP_W, MINIMAP_H)), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(origin, Vector2(MINIMAP_W, MINIMAP_H)), Color(0.75, 0.62, 0.35, 0.8), false, 1.5)
	draw_string(f, origin + Vector2(8, 16), "던전 지도", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.9, 0.7))
	# 격자 범위
	var gmin := Vector2i(1000000, 1000000)
	var gmax := Vector2i(-1000000, -1000000)
	for r in d.rooms:
		gmin = Vector2i(mini(gmin.x, r.grid.x), mini(gmin.y, r.grid.y))
		gmax = Vector2i(maxi(gmax.x, r.grid.x), maxi(gmax.y, r.grid.y))
	var cols := gmax.x - gmin.x + 1
	var rows := gmax.y - gmin.y + 1
	var cell := 40.0
	var gap := 6.0
	var map_w := cols * cell + (cols - 1) * gap
	var map_h := rows * cell + (rows - 1) * gap
	var base := origin + Vector2((MINIMAP_W - map_w) * 0.5, 24.0 + (MINIMAP_H - 48.0 - map_h) * 0.5)
	var centers := {}
	for r in d.rooms:
		var g := r.grid - gmin
		centers[r.id] = base + Vector2(g.x * (cell + gap) + cell * 0.5, g.y * (cell + gap) + cell * 0.5)
	# 연결선(문): 현재 방이 잠겨 있으면 그 방의 문은 막힌 선 + 자물쇠
	var drawn := {}
	for r in d.rooms:
		for cid in r.connections:
			var key := "%s|%s" % [mini(hash(r.id), hash(cid)), maxi(hash(r.id), hash(cid))]
			if drawn.has(key) or not centers.has(cid):
				continue
			drawn[key] = true
			var a: Vector2 = centers[r.id]
			var b: Vector2 = centers[cid]
			var locked := battle.doors_locked and (r.id == battle.room.id or cid == battle.room.id)
			if locked:
				draw_line(a, b, Color(0.9, 0.25, 0.2, 0.9), 2.0)
				var m := (a + b) * 0.5
				draw_line(m + Vector2(-4, -4), m + Vector2(4, 4), Color(1, 0.85, 0.3), 2.0)
				draw_line(m + Vector2(-4, 4), m + Vector2(4, -4), Color(1, 0.85, 0.3), 2.0)
			else:
				draw_line(a, b, Color(0.5, 0.9, 0.55, 0.9), 2.0)
	# 방 상자
	for r in d.rooms:
		var c: Vector2 = centers[r.id]
		var rect := Rect2(c - Vector2(cell, cell) * 0.5, Vector2(cell, cell))
		var st := battle.room_state(r.id)
		var visited: bool = st.visited
		var cleared: bool = st.cleared
		var fill := Color(0.35, 0.35, 0.4, 0.5) if not visited else Color(0.55, 0.5, 0.42, 0.95)
		if r.kind == &"boss":
			fill = Color(0.5, 0.2, 0.22, 0.6 if not visited else 0.95)
		elif r.kind == &"treasure":
			fill = Color(0.5, 0.45, 0.2, 0.6 if not visited else 0.95)
		draw_rect(rect, fill)
		var border := Color(0.7, 0.7, 0.7, 0.6) if not visited else Color(0.9, 0.85, 0.7)
		if r.id == battle.room.id:
			border = Color(1.0, 0.95, 0.4)
			draw_rect(rect.grow(2.0), border, false, 3.0)
			draw_circle(c + Vector2(0, cell * 0.28), 4.0, Color(1.0, 0.95, 0.4))
		else:
			draw_rect(rect, border, false, 1.5)
		var glyph := ""
		match r.kind:
			&"entry": glyph = "입"
			&"boss": glyph = "B"
			&"treasure": glyph = "?" if not visited else ""
			&"battle": glyph = str(r.grid.x - gmin.x)
		if glyph != "":
			draw_string(f, c + Vector2(-5, 5), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		if r.kind == &"treasure" and visited:
			# 상자 아이콘: 닫힘/열림
			var cr := Rect2(c + Vector2(-9, -4), Vector2(18, 10))
			draw_rect(cr, Color(0.7, 0.5, 0.25))
			if battle.chest_opened:
				draw_rect(Rect2(c + Vector2(-9, -12), Vector2(18, 5)), Color(0.85, 0.65, 0.3))
			else:
				draw_rect(Rect2(c + Vector2(-9, -9), Vector2(18, 5)), Color(0.55, 0.38, 0.2))
		if cleared:
			# 정리 완료 체크
			draw_line(c + Vector2(6, -14), c + Vector2(11, -9), Color(0.5, 1.0, 0.5), 2.5)
			draw_line(c + Vector2(11, -9), c + Vector2(18, -18), Color(0.5, 1.0, 0.5), 2.5)
	# 현재 방 웨이브/남은 적 짧은 문구(지도와 별도)
	var line := battle.room.display_name
	if battle.room.kind == &"battle" and battle.doors_locked:
		line += "  %d/%d 웨이브 · 남은 적 %d" % [mini(battle.wave_index, battle.total_waves()), battle.total_waves(), battle.required_alive_count()]
	elif battle.room.kind == &"boss" and battle.doors_locked:
		line += "  보스 남은 적 %d" % battle.required_alive_count()
	elif battle.is_room_cleared(battle.room.id):
		line += "  정리 완료"
	draw_string(f, origin + Vector2(8, MINIMAP_H - 8), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.95, 0.85))

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
	if not p.alive and battle.mode == &"training":
		draw_string(f, Vector2(480, 200), "쓰러졌다 — F6 으로 초기화", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 0.5, 0.5))
	if battle.paused:
		draw_string(f, Vector2(560, 300), "일시정지 (Esc)", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1))
	# --- 우상단: 조작 안내
	var help := [
		"방향키 이동   X 평타   C 점프(공중 평타 1회)   Space 회피",
		"A 돌진베기  S 올려베기  D 내려베기  F 회전베기  Q 방어깨기  W 검기  E 흘려받기  R 일섬연무 (모두 지상)",
	]
	if battle.mode == &"campaign":
		help.append("Enter 문 이동 / 상자 열기 (지상에서)   Esc 일시정지")
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
	if battle.mode == &"campaign":
		_draw_campaign(f)
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
			if sd.hint != "":
				draw_string(f, r.position + Vector2(8, 37), sd.hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.75))
			if cd > 0:
				var frac := float(cd) / float(maxi(1, total))
				draw_rect(Rect2(r.position.x, r.position.y + r.size.y * (1.0 - frac), r.size.x, r.size.y * frac), Color(0, 0, 0, 0.55))
				draw_string(f, r.position + Vector2(8, 54), "%.1f 초" % (Ticks.to_ms(cd) / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.6, 0.6))
			else:
				draw_string(f, r.position + Vector2(8, 54), "준비됨 (%.0f초)" % (sd.cooldown_ms / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 1.0, 0.6))
			# 현재 시전 중인 칸 강조
			if p.current_skill == sd and (p.state == &"skill" or p.state == &"guard"):
				draw_rect(r, Color(1.0, 0.95, 0.5), false, 3.0)
		i += 1
	# 흘려받기 결과·일섬연무 타격 수(스킬 칸 위, 도형+문구)
	if p.guard_fx_ticks > 0 and p.last_guard_result != "":
		var ok := p.last_guard_result.ends_with("성공")
		var gx := x0 + 220.0
		draw_rect(Rect2(gx, y0 - 30, 210, 22), Color(0, 0, 0, 0.5))
		if ok:
			draw_line(Vector2(gx + 8, y0 - 19), Vector2(gx + 14, y0 - 13), Color(0.5, 0.9, 1.0), 3.0)
			draw_line(Vector2(gx + 14, y0 - 13), Vector2(gx + 24, y0 - 26), Color(0.5, 0.9, 1.0), 3.0)
		else:
			draw_line(Vector2(gx + 8, y0 - 26), Vector2(gx + 22, y0 - 12), Color(1.0, 0.6, 0.5), 3.0)
			draw_line(Vector2(gx + 8, y0 - 12), Vector2(gx + 22, y0 - 26), Color(1.0, 0.6, 0.5), 3.0)
		draw_string(f, Vector2(gx + 30, y0 - 14), p.last_guard_result, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.9, 1.0) if ok else Color(1.0, 0.7, 0.6))
	if p.state == &"skill" and p.current_attack != null and p.current_attack.multi_hits > 0:
		var n: int = p.multi_fired.size()
		var rx := x0 + 440.0
		draw_rect(Rect2(rx, y0 - 30, 150, 22), Color(0, 0, 0, 0.5))
		for k in p.current_attack.multi_hits:
			var c := Color(1.0, 0.9, 0.4) if k < n else Color(0.4, 0.4, 0.4)
			draw_circle(Vector2(rx + 12 + k * 14, y0 - 19), 5.0, c)
		draw_string(f, Vector2(rx + 84, y0 - 14), "연무 %d/%d" % [n, p.current_attack.multi_hits], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.7))
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

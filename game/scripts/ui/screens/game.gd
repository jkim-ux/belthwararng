class_name Game
extends Control
## 게임 루트: 시작 화면 → 지도 → 관리 / 거점 전투 → 결과 → 합류 → 동료 선택. 수련장은 캠페인 저장과 분리된다.
## 화면은 코드로 만든 Control 이며 마우스와 키보드(방향키·Enter)로 조작한다.
## 사용자 인자: --training / --demo (수련장 바로 시작), --save=경로 (다른 저장 파일 사용, 테스트용)

const BATTLE_SCENE := "res://scenes/battle.tscn"
const BASE_ATTACK := 20.0
const BASE_MAX_HP := 100

var campaign: CampaignController
var ui_theme: Theme
var screen_root: Control
var battle_holder: Node2D
var overlay_root: Control
var battle: Battle
var current_screen: String = ""
var pending_join_companion: String = ""
var last_result: Dictionary = {}
var _pause_overlay: Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_theme = Theme.new()
	ui_theme.default_font = UiFont.FONT
	ui_theme.default_font_size = 16
	theme = ui_theme
	battle_holder = Node2D.new()
	battle_holder.name = "BattleHolder"
	add_child(battle_holder)
	screen_root = Control.new()
	screen_root.name = "Screens"
	screen_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen_root)
	overlay_root = Control.new()
	overlay_root.name = "Overlays"
	overlay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_root)
	var save_path := CampaignController.DEFAULT_SAVE_PATH
	var go_training := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--save="):
			save_path = a.trim_prefix("--save=")
		elif a == "--training" or a == "--demo":
			go_training = true
	campaign = CampaignController.new(save_path)
	if go_training:
		start_training()
	else:
		show_title()

# ------------------------------------------------------------------ 공통 위젯

func _clear_screen() -> void:
	for c in screen_root.get_children():
		c.queue_free()
	for c in overlay_root.get_children():
		c.queue_free()
	_pause_overlay = null

func _close_battle() -> void:
	if battle != null and is_instance_valid(battle):
		battle.queue_free()
	battle = null

func _panel(rect: Rect2, color: Color = Color(0.09, 0.08, 0.11, 0.94)) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = Color(0.75, 0.62, 0.35)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	p.position = rect.position
	p.size = rect.size
	return p

## 세로 목록용 라벨(줄바꿈 허용). 가로 행(HBox) 안에는 _hlabel 을 쓴다.
func _label(text: String, size: int = 16, color: Color = Color(0.95, 0.93, 0.88)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## 가로 행용 라벨: 줄바꿈 없이 내용 폭만큼 차지한다.
func _hlabel(text: String, size: int = 16, color: Color = Color(0.95, 0.93, 0.88)) -> Label:
	var l := _label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

func _button(text: String, on_pressed: Callable, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(0, 36)
	b.pressed.connect(on_pressed)
	return b

func _hbox() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	return h

func _vbox() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	return v

func _background(title: String) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.11, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_root.add_child(bg)
	var panel := _panel(Rect2(60, 40, 1160, 640))
	screen_root.add_child(panel)
	var v := _vbox()
	panel.add_child(v)
	v.add_child(_label(title, 28, Color(1.0, 0.9, 0.65)))
	return v

# ------------------------------------------------------------------ 시작 화면

func show_title() -> void:
	_close_battle()
	_clear_screen()
	current_screen = "title"
	var v := _background("사무라이 점령전")
	v.add_child(_label("첫 마을에서 시작하는 반격. 챕터 1 '꺼진 봉화' — 농촌 → 창고 마을 → 고개 초소. 거점마다 방 던전(입구 → 전투 3 → 보스, 선택 보물방). 적 피해 2배·강인병·액티브 8개.", 16))
	v.add_child(_label("HWR-004 R1 · 전투 기획 v0.5", 13, Color(0.7, 0.7, 0.7)))
	v.add_child(HSeparator.new())
	var has_save := campaign.has_save()
	v.add_child(_button("새 게임", _on_new_game))
	v.add_child(_button("이어하기" + ("" if has_save else " (저장 없음)"), _on_continue, has_save))
	v.add_child(_button("수련장 (프로필 비교 · 허수아비/근접병/강인병 표적 · 8스킬 · 저장 없음)", start_training))
	v.add_child(HSeparator.new())
	v.add_child(_label("조작: 방향키 이동, X 평타, C 점프, Space 회피, A 돌진베기, S 올려베기, D 내려베기, F 회전베기, Q 방어깨기, W 검기, E 흘려받기, R 일섬연무, Enter 문 이동/상자, Esc 일시정지.", 13, Color(0.75, 0.75, 0.75)))
	v.add_child(_label("저장 파일: %s" % campaign.store.path, 12, Color(0.55, 0.55, 0.55)))
	if campaign.last_load_message != "":
		v.add_child(_label(campaign.last_load_message, 13, Color(1.0, 0.7, 0.6)))

func _on_new_game() -> void:
	if campaign.has_save():
		var dlg := ConfirmationDialog.new()
		dlg.title = "새 게임"
		dlg.dialog_text = "기존 저장을 덮어씁니다. 계속할까요?"
		dlg.ok_button_text = "덮어쓰기"
		dlg.cancel_button_text = "취소"
		dlg.confirmed.connect(_start_new_game)
		add_child(dlg)
		dlg.popup_centered()
		return
	_start_new_game()

func _start_new_game() -> void:
	var r := campaign.new_game()
	if not r.ok:
		show_title()
		campaign.last_load_message = "새 게임 저장 실패: %s" % r.error
		return
	show_map("새 게임을 시작했다. 군자금 0. 농촌부터 되찾자.")

func _on_continue() -> void:
	var r := campaign.continue_game()
	if not r.ok:
		_show_load_failure(r.error)
		return
	var msg := "이어하기."
	if r.recovered_from_backup:
		msg = "주 저장이 손상되어 백업에서 복구했다. " + r.error
	elif r.error != "":
		msg = r.error
	show_map(msg)

func _show_load_failure(error: String) -> void:
	_clear_screen()
	var v := _background("저장을 읽을 수 없음")
	v.add_child(_label(error, 15, Color(1.0, 0.7, 0.6)))
	v.add_child(_label("손상된 저장은 자동으로 덮어쓰지 않는다. 새 게임을 시작하거나 취소할 수 있다.", 14))
	v.add_child(_button("새 게임 (기존 파일 덮어쓰기)", _start_new_game))
	v.add_child(_button("취소 (시작 화면)", show_title))

# ------------------------------------------------------------------ 지도

func show_map(message: String = "") -> void:
	_close_battle()
	_clear_screen()
	current_screen = "map"
	var st := campaign.state
	var data := campaign.data
	var v := _background("섬의 지도 — 전선")
	var head := _hbox()
	head.add_child(_hlabel("군자금 %d" % st.currency, 18, Color(1.0, 0.9, 0.5)))
	var comp := campaign.selected_companion()
	head.add_child(_hlabel("동행: %s" % (comp.display_name if comp else "없음 (혼자 출정)"), 16))
	head.add_child(_hlabel("공격력 %.0f · 최대 체력 %d" % [campaign.player_attack_power(BASE_ATTACK), campaign.player_max_hp(BASE_MAX_HP)], 14, Color(0.8, 0.9, 0.8)))
	v.add_child(head)
	if message != "":
		v.add_child(_label(message, 14, Color(0.8, 0.95, 0.8)))
	if campaign.has_pending():
		v.add_child(_label("미저장 결과가 있다. 저장을 재시도하거나 이전 저장으로 돌아가야 출정할 수 있다.", 14, Color(1.0, 0.6, 0.5)))
		var hb := _hbox()
		hb.add_child(_button("저장 재시도", func(): _retry_pending_from_map()))
		hb.add_child(_button("이전 저장으로", func(): campaign.discard_pending(); show_map("이전 저장으로 돌아갔다.")))
		v.add_child(hb)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 430)
	v.add_child(scroll)
	var list := _vbox()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for ch in data.chapters:
		var status := ""
		var col := Color(0.9, 0.9, 0.9)
		if st.is_chapter_cleared(ch.id):
			status = "클리어"
			col = Color(0.6, 1.0, 0.6)
		elif not ch.implemented:
			status = "콘텐츠 준비 중 (조건을 만족해도 진입 불가)"
			col = Color(0.6, 0.6, 0.6)
		elif ch.prerequisite_chapter_id != &"" and not st.is_chapter_cleared(ch.prerequisite_chapter_id):
			status = "잠김: 챕터 %d 클리어 필요" % data.chapter(ch.prerequisite_chapter_id).index
			col = Color(0.8, 0.7, 0.6)
		else:
			status = "진행 중"
			col = Color(1.0, 0.9, 0.6)
		list.add_child(_label("챕터 %d  %s — %s" % [ch.index, ch.display_name, status], 18, col))
		list.add_child(_label(ch.summary, 13, Color(0.7, 0.7, 0.7)))
		var reward := data.companion(ch.reward_companion_id)
		if reward != null:
			list.add_child(_label("클리어 보상 동료: %s (%s)%s" % [reward.display_name, reward.role, " — 해금됨" if st.is_companion_unlocked(reward.id) else ""], 13, Color(0.75, 0.85, 0.95)))
		for site in data.sites_of_chapter(ch.id):
			list.add_child(_site_row(site))
		list.add_child(HSeparator.new())
	var foot := _hbox()
	foot.add_child(_button("동료 선택", func(): show_companions(), not st.unlocked_companions.is_empty()))
	foot.add_child(_button("시작 화면으로", show_title))
	v.add_child(foot)

func _site_row(site: SiteDef) -> Control:
	var st := campaign.state
	var row := _hbox()
	var own := "해방 완료" if st.is_liberated(site.id) else "점령 중"
	var kind := "마을" if site.is_village() else "군사 거점"
	var text := "  · %s [%s]  %s" % [site.display_name, kind, own]
	if site.is_village():
		text += "  관리도 %d" % st.management(site.id)
	var chk := st.can_enter_site(site, campaign.data)
	var l := _hlabel(text, 15, Color(0.95, 0.95, 0.9) if chk.ok or st.is_liberated(site.id) else Color(0.7, 0.7, 0.7))
	l.custom_minimum_size = Vector2(520, 0)
	row.add_child(l)
	if chk.ok:
		row.add_child(_button("출정" + (" (재도전 +%d)" % site.repeat_reward if st.is_liberated(site.id) else " (최초 +%d)" % site.first_reward), func(): start_battle(site.id), not campaign.has_pending()))
	else:
		row.add_child(_hlabel("진입 조건: %s" % chk.reason, 13, Color(0.9, 0.75, 0.6)))
	if site.is_village() and st.is_liberated(site.id):
		row.add_child(_button("관리", func(): show_manage(site.id)))
	return row

func _retry_pending_from_map() -> void:
	var r := campaign.retry_pending()
	show_map("저장 성공. 결과가 반영되었다." if r.saved else "저장 재시도 실패: %s" % r.reason)

# ------------------------------------------------------------------ 마을 관리

class VillageScene extends Control:
	var site: SiteDef
	var liberated := false
	var repaired := false
	var facility_bought := false
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.55, 0.62, 0.75) if liberated else Color(0.35, 0.3, 0.32))
		draw_rect(Rect2(0, h * 0.55, w, h * 0.45), Color(0.45, 0.6, 0.3) if repaired else (Color(0.55, 0.5, 0.35) if liberated else Color(0.4, 0.35, 0.3)))
		var is_farm := site != null and site.id == &"ch1_farm"
		# 논밭/수로 또는 창고 지붕/짐수레
		if is_farm:
			for i in 6:
				var y := h * 0.6 + i * 14.0
				draw_line(Vector2(20, y), Vector2(w * 0.55, y), Color(0.3, 0.5, 0.2) if repaired else Color(0.5, 0.42, 0.3), 3.0)
			if repaired:
				draw_line(Vector2(w * 0.58, h * 0.55), Vector2(w * 0.58, h), Color(0.4, 0.6, 0.9), 6.0)
		else:
			var roof_col := Color(0.5, 0.3, 0.2) if repaired else Color(0.35, 0.3, 0.28)
			draw_rect(Rect2(w * 0.1, h * 0.35, w * 0.35, h * 0.3), Color(0.6, 0.55, 0.45))
			if repaired:
				draw_colored_polygon(PackedVector2Array([Vector2(w * 0.08, h * 0.36), Vector2(w * 0.275, h * 0.2), Vector2(w * 0.47, h * 0.36)]), roof_col)
			else:
				draw_line(Vector2(w * 0.08, h * 0.36), Vector2(w * 0.2, h * 0.24), roof_col, 5.0)
				draw_line(Vector2(w * 0.34, h * 0.28), Vector2(w * 0.47, h * 0.36), roof_col, 5.0)
			if repaired:
				draw_rect(Rect2(w * 0.6, h * 0.72, 60, 24), Color(0.55, 0.4, 0.25))
				draw_circle(Vector2(w * 0.6 + 12, h * 0.72 + 28), 8, Color(0.2, 0.2, 0.2))
				draw_circle(Vector2(w * 0.6 + 48, h * 0.72 + 28), 8, Color(0.2, 0.2, 0.2))
		# 깃발: 점령 중 적 깃발(검붉은) / 해방 후 새 깃발(흰·남색)
		var fx := w * 0.85
		draw_line(Vector2(fx, h * 0.25), Vector2(fx, h * 0.8), Color(0.3, 0.25, 0.2), 3.0)
		draw_rect(Rect2(fx, h * 0.25, 40, 26), Color(0.25, 0.75, 0.9) if liberated else Color(0.6, 0.1, 0.1))
		# 주민(작은 도형): 점령 중에는 없음, 해방 후 2명, 정비 후 4명 + 시설 시 표시
		var n := 0 if not liberated else (4 if repaired else 2)
		for i in n:
			var px := w * 0.62 + i * 26.0
			var py := h * 0.9
			draw_rect(Rect2(px - 6, py - 22, 12, 22), Color(0.9, 0.85, 0.7))
			draw_circle(Vector2(px, py - 28), 6, Color(0.95, 0.85, 0.7))
		if facility_bought:
			draw_rect(Rect2(w * 0.05, h * 0.05, 120, 22), Color(0, 0, 0, 0.4))
			draw_string(UiFont.FONT, Vector2(w * 0.05 + 6, h * 0.05 + 16), "시설 가동 중", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 0.8))

func show_manage(site_id: StringName, message: String = "") -> void:
	_close_battle()
	_clear_screen()
	current_screen = "manage"
	var st := campaign.state
	var data := campaign.data
	var site := data.site(site_id)
	if site == null or not site.is_village() or not st.is_liberated(site.id):
		show_map("관리할 수 없는 거점")
		return
	var v := _background("%s — 마을 관리" % site.display_name)
	var scene := VillageScene.new()
	scene.site = site
	scene.liberated = true
	scene.repaired = st.is_repaired(site.id)
	scene.facility_bought = site.facility != null and st.has_facility(site.facility.id)
	scene.custom_minimum_size = Vector2(1120, 130)
	v.add_child(scene)
	var scene_text := site.scene_repaired if scene.repaired else site.scene_liberated
	v.add_child(_label(scene_text, 14, Color(0.85, 0.9, 0.85)))
	var head := _hbox()
	head.add_child(_hlabel("관리도 %d / 60" % st.management(site.id), 18, Color(0.8, 1.0, 0.8)))
	head.add_child(_hlabel("군자금 %d" % st.currency, 18, Color(1.0, 0.9, 0.5)))
	v.add_child(head)
	if message != "":
		v.add_child(_label(message, 14, Color(1.0, 0.85, 0.6)))
	# 정비
	var rep := st.can_repair(site)
	var rep_row := _hbox()
	rep_row.add_child(_button("정비 (-%d)  관리도 40 → 60" % site.repair_cost, func(): _do_repair(site.id), rep.ok))
	rep_row.add_child(_hlabel("완료" if st.is_repaired(site.id) else rep.reason, 13, Color(0.7, 0.9, 0.7) if st.is_repaired(site.id) else Color(0.85, 0.75, 0.6)))
	v.add_child(rep_row)
	# 시설
	if site.facility != null:
		var f := site.facility
		var fchk := st.can_buy_facility(site)
		var frow := _hbox()
		frow.add_child(_button("%s (-%d)  %s" % [f.display_name, f.cost, f.description], func(): _do_buy(site.id), fchk.ok))
		frow.add_child(_hlabel("구매 완료" if st.has_facility(f.id) else fchk.reason, 13, Color(0.7, 0.9, 0.7) if st.has_facility(f.id) else Color(0.85, 0.75, 0.6)))
		v.add_child(frow)
		v.add_child(_label("주민: " + f.villagers_text, 13, Color(0.75, 0.75, 0.75)))
	# 다음 거점 조건
	for other in data.sites:
		if other.prerequisite_site_id == site.id:
			var chk := st.can_enter_site(other, data)
			v.add_child(_label("다음 거점 %s: %s" % [other.display_name, "진입 가능" if chk.ok else chk.reason], 14, Color(0.8, 0.9, 1.0)))
	v.add_child(_label("출정 시 효과: 공격력 %.0f, 최대 체력 %d (저장된 구매 플래그에서 계산)" % [campaign.player_attack_power(BASE_ATTACK), campaign.player_max_hp(BASE_MAX_HP)], 13, Color(0.7, 0.8, 0.7)))
	var foot := _hbox()
	foot.add_child(_button("출정 (재도전 +%d)" % site.repeat_reward, func(): start_battle(site.id), not campaign.has_pending()))
	foot.add_child(_button("지도로", func(): show_map()))
	v.add_child(foot)

func _do_repair(site_id: StringName) -> void:
	var r := campaign.repair(site_id)
	var msg := "정비 완료. 관리도 60." if r.ok and r.saved else ("정비 거부: %s" % r.reason if not r.ok else "정비 저장 실패: %s" % r.reason)
	show_manage(site_id, msg)

func _do_buy(site_id: StringName) -> void:
	var r := campaign.buy_facility(site_id)
	var msg := "시설 구매 완료. 효과는 다음 출정부터 적용." if r.ok and r.saved else ("구매 거부: %s" % r.reason if not r.ok else "구매 저장 실패: %s" % r.reason)
	show_manage(site_id, msg)

# ------------------------------------------------------------------ 전투

func start_training() -> void:
	_close_battle()
	_clear_screen()
	current_screen = "training"
	var b: Battle = load(BATTLE_SCENE).instantiate()
	b.mode = &"training"
	battle = b
	battle_holder.add_child(b)
	var back := _button("시작 화면으로 (수련장 종료)", show_title)
	back.position = Vector2(1060, 118)
	back.size = Vector2(200, 30)
	overlay_root.add_child(back)

func start_battle(site_id: StringName) -> void:
	var r := campaign.begin_run(site_id)
	if not r.ok:
		show_map("출정 거부: %s" % r.reason)
		return
	_close_battle()
	_clear_screen()
	current_screen = "battle"
	var site := campaign.data.site(site_id)
	var b: Battle = load(BATTLE_SCENE).instantiate()
	b.mode = &"campaign"
	b.debug_visible = false
	battle = b
	battle_holder.add_child(b)
	b.start_encounter(site, r.run_id, campaign.selected_companion(), campaign.player_attack_power(BASE_ATTACK), campaign.player_max_hp(BASE_MAX_HP))
	b.resolved.connect(_on_battle_resolved)

func _process(_delta: float) -> void:
	if current_screen != "battle" or battle == null or not is_instance_valid(battle):
		return
	if battle.result_state != &"active":
		return
	if battle.paused and _pause_overlay == null:
		_show_pause_overlay()
	elif not battle.paused and _pause_overlay != null:
		_pause_overlay.queue_free()
		_pause_overlay = null

func _show_pause_overlay() -> void:
	var p := _panel(Rect2(440, 250, 400, 190))
	var v := _vbox()
	p.add_child(v)
	v.add_child(_label("일시정지", 22, Color(1.0, 0.9, 0.65)))
	v.add_child(_button("계속 (Esc)", func(): battle.paused = false))
	v.add_child(_button("출정 포기 (보상 없이 지도로)", func(): battle.paused = false; battle.abandon()))
	overlay_root.add_child(p)
	_pause_overlay = p

func _on_battle_resolved(outcome: StringName, run_id: String) -> void:
	var extras := {}
	if battle != null and is_instance_valid(battle):
		extras = {"chest_bonus": battle.pending_currency, "chest_opened": battle.chest_opened, "run_stats": battle.run_stats.duplicate(true)}
	var result := campaign.resolve_run(run_id, outcome, extras)
	last_result = result
	_show_result(result)

func _show_result(result: Dictionary) -> void:
	for c in overlay_root.get_children():
		c.queue_free()
	_pause_overlay = null
	var p := _panel(Rect2(340, 150, 600, 400))
	var v := _vbox()
	p.add_child(v)
	var outcome := String(result.get("outcome", ""))
	var site := campaign.data.site(StringName(String(result.get("site_id", ""))))
	var site_name := site.display_name if site else ""
	match outcome:
		"victory":
			v.add_child(_label("승리 — %s" % site_name, 26, Color(1.0, 0.9, 0.5)))
			var bonus := int(result.get("chest_bonus", 0))
			var bonus_text := ("  (기본 %d + 상자 %d)" % [int(result.get("base_reward", result.reward)), bonus]) if bonus > 0 else ""
			if result.get("liberated_now", false):
				v.add_child(_label("보스 격파 — %s 해방! 최초 보상 군자금 +%d%s" % [site_name, result.reward, bonus_text], 16, Color(0.8, 1.0, 0.8)))
				if site and site.is_village():
					v.add_child(_label("관리도 40. 마을 관리에서 정비(40)하면 60이 되어 다음 거점이 열린다.", 14))
			else:
				v.add_child(_label("보스 격파 — 재도전 승리. 군자금 +%d%s (점령·관리·해금은 그대로)" % [result.reward, bonus_text], 16, Color(0.8, 1.0, 0.8)))
			if String(result.get("chapter_cleared", "")) != "":
				v.add_child(_label("챕터 클리어! 봉화가 켜졌다.", 18, Color(1.0, 0.8, 0.4)))
			if String(result.get("companion_unlocked", "")) != "":
				var c := campaign.data.companion(StringName(String(result.companion_unlocked)))
				v.add_child(_label("동료 해금: %s" % (c.display_name if c else String(result.companion_unlocked)), 18, Color(0.7, 0.9, 1.0)))
		"defeat":
			v.add_child(_label("패배 — %s" % site_name, 26, Color(1.0, 0.5, 0.5)))
			v.add_child(_label("보상 없음(상자 보류 군자금도 소멸). 이전 점령·시설·자금은 유지된다. 재도전은 새 출정으로.", 15))
		"abandon":
			v.add_child(_label("출정 포기 — %s" % site_name, 26, Color(0.9, 0.8, 0.6)))
			v.add_child(_label("보상 없이(상자 보류 군자금 소멸) 지도로 돌아간다.", 15))
		_:
			v.add_child(_label("결과: %s" % String(result.get("status", "")), 20))
	v.add_child(_label("군자금 %d" % int(result.get("currency", campaign.state.currency)), 16, Color(1.0, 0.9, 0.5)))
	var status := String(result.get("status", ""))
	if status == "unsaved":
		v.add_child(_label("⚠ 저장되지 않음: %s" % String(result.reason), 15, Color(1.0, 0.6, 0.5)))
		v.add_child(_label("보상은 저장이 성공해야 확정된다. 재시도해도 보상을 다시 더하지 않는다.", 13))
		v.add_child(_button("저장 재시도", _retry_pending_from_result))
		v.add_child(_button("이전 저장으로 돌아가기 (이번 결과 미반영)", func(): campaign.discard_pending(); show_map("이전 저장으로 돌아갔다. 이번 결과는 반영되지 않았다.")))
	elif status == "duplicate":
		v.add_child(_label("이미 반영된 출정 결과", 14, Color(0.8, 0.8, 0.8)))
	else:
		v.add_child(_button("확인", _after_result))
	overlay_root.add_child(p)

func _retry_pending_from_result() -> void:
	var r := campaign.retry_pending()
	last_result = r
	_show_result(r)

func _after_result() -> void:
	var r := last_result
	if String(r.get("status", "")) == "committed" and String(r.get("companion_unlocked", "")) != "":
		show_join(String(r.companion_unlocked))
	else:
		show_map()

# ------------------------------------------------------------------ 합류·동료 선택

func show_join(companion_id: String) -> void:
	_close_battle()
	_clear_screen()
	current_screen = "join"
	pending_join_companion = companion_id
	var c := campaign.data.companion(StringName(companion_id))
	var v := _background("합류 — %s" % (c.display_name if c else companion_id))
	var portrait := ColorRect.new()
	portrait.color = Color(0.35, 0.7, 0.45)
	portrait.custom_minimum_size = Vector2(120, 120)
	v.add_child(portrait)
	if c != null:
		v.add_child(_label(c.join_text, 17))
		v.add_child(_label("역할: %s. %s" % [c.role, c.description], 14, Color(0.8, 0.8, 0.8)))
	v.add_child(_label("해금과 선택은 별개다. 동료 선택에서 동행을 정한 뒤 해방된 거점을 재도전하면 함께 싸운다.", 14, Color(0.8, 0.9, 1.0)))
	v.add_child(_button("동료 선택으로", func(): show_companions("", true)))

func show_companions(message: String = "", offer_retry: bool = false) -> void:
	_close_battle()
	_clear_screen()
	current_screen = "companions"
	var st := campaign.state
	var data := campaign.data
	var v := _background("동료 선택 — 1명 동행 또는 혼자 출정")
	if message != "":
		v.add_child(_label(message, 14, Color(1.0, 0.85, 0.6)))
	var none_row := _hbox()
	none_row.add_child(_hlabel("혼자 출정" + ("  [현재 선택]" if st.selected_companion_id == "" else ""), 16))
	none_row.add_child(_button("선택", func(): _select_companion(&"")))
	v.add_child(none_row)
	for c in data.companions:
		var row := _hbox()
		var unlocked := st.is_companion_unlocked(c.id)
		var selectable := unlocked and c.implemented
		var ch := data.chapter(c.unlock_chapter_id)
		var status := "선택 가능" if selectable else ("해금됨 · 미구현" if unlocked else "잠김: 챕터 %d 클리어" % (ch.index if ch else 0))
		var col := Color(0.95, 0.95, 0.9) if selectable else Color(0.6, 0.6, 0.6)
		var l := _hlabel("%s — %s  (%s)%s" % [c.display_name, c.role, status, "  [현재 선택]" if st.selected_companion_id == String(c.id) else ""], 16, col)
		l.custom_minimum_size = Vector2(700, 0)
		row.add_child(l)
		row.add_child(_button("선택", func(): _select_companion(c.id), selectable))
		v.add_child(row)
		v.add_child(_label("    " + c.description, 13, Color(0.7, 0.7, 0.7)))
	v.add_child(HSeparator.new())
	if offer_retry or not st.unlocked_companions.is_empty():
		var farm := data.site(&"ch1_farm")
		var aya_ok: bool = st.can_select_companion(&"aya", data).ok
		v.add_child(_label("바로 체험: 아야를 선택하고 해방된 농촌을 재도전한다 (자동 재도전 아님, 버튼을 눌러야 시작).", 14, Color(0.8, 0.9, 1.0)))
		v.add_child(_button("아야와 농촌 재도전", func(): _select_companion(&"aya", false); start_battle(&"ch1_farm"), aya_ok and farm != null and st.is_liberated(&"ch1_farm")))
	v.add_child(_button("지도로", func(): show_map()))

func _select_companion(id: StringName, refresh: bool = true) -> void:
	var r := campaign.select_companion(id)
	if refresh:
		var msg := "동행: %s" % (campaign.selected_companion().display_name if campaign.selected_companion() else "없음")
		if not r.ok:
			msg = "선택 거부: %s" % r.reason
		elif not r.saved:
			msg = "선택 저장 실패: %s" % r.reason
		show_companions(msg)

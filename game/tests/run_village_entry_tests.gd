extends SceneTree
## UI 진입·실제 저장 분리·재입장·정상 캠페인 잠금 회귀 확인.
const SAVE := "user://test_saves/hwr006_village_entry.json"
const CLI_SAVE := "user://test_saves/hwr006_village_cli.json"
var failed := 0
var passed := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error(description)

func clean(path: String) -> void:
	SaveStore.new(path).delete_all()
	SaveStore.new(path + Game.VILLAGE_TEST_SUFFIX).delete_all()

func button_in(node: Node, prefix: String) -> Button:
	if node.is_queued_for_deletion(): return null
	if node is Button and node.text.begins_with(prefix): return node
	for child in node.get_children():
		var b := button_in(child, prefix)
		if b != null: return b
	return null

func click(button: Button) -> void:
	check(button != null and not button.disabled, "UI button exists and is enabled")
	if button == null: return
	var px := button.get_global_rect().get_center()
	check(root.get_visible_rect().has_point(px), "UI button is inside the viewport")
	var motion := InputEventMouseMotion.new()
	motion.position = px
	motion.global_position = px
	root.push_input(motion)
	await process_frame
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = px
		event.global_position = px
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event)
		await process_frame
	await process_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	if "--check-cli" in OS.get_cmdline_user_args():
		clean(CLI_SAVE)
		var cli_game: Game = load("res://scenes/main.tscn").instantiate()
		root.add_child(cli_game)
		await process_frame
		check(cli_game.current_screen == "village" and cli_game.battle == null, "--village-test enters the village without battle")
		check(cli_game.campaign.store.path == CLI_SAVE + Game.VILLAGE_TEST_SUFFIX, "--save applies to the isolated test slot")
		check(not FileAccess.file_exists(CLI_SAVE), "CLI entry does not create a campaign save")
		cli_game.show_title()
		await process_frame
		cli_game.free()
		clean(CLI_SAVE)
		finish()
		return
	clean(SAVE)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	var normal := CampaignController.new(SAVE)
	check(normal.new_game().ok, "Normal test save created")
	g.campaign = normal
	g.show_title()
	await process_frame
	await process_frame
	var original := FileAccess.get_file_as_bytes(SAVE)
	var memory := JSON.stringify(normal.state.to_dict())
	check(not normal.enter_village(&"ch1_farm").ok, "Normal campaign still requires liberation")
	await click(button_in(g, "마을 바로 테스트"))
	check(g.current_screen == "village" and g.battle == null, "Title button opens village directly")
	if g.village_view == null:
		g.free()
		clean(SAVE)
		finish()
		return
	check(g.village_view.test_mode, "Village displays test mode")
	check(g.campaign != normal and g.campaign.store.path == SAVE + Game.VILLAGE_TEST_SUFFIX, "Separate controller and save path")
	check(g.campaign.active_village == &"ch1_farm", "First village active")
	check(g.campaign.active_village_state().villagers.size() == 3, "Three working spirits available")
	check(g.campaign.state.wood >= 300 and g.campaign.state.currency >= 1000, "Construction supplies available")
	check(FileAccess.get_file_as_bytes(SAVE) == original and JSON.stringify(normal.state.to_dict()) == memory, "Entry preserves normal save and in-memory progress")
	var placed := g.campaign.village_place(&"well", 10, 4, 0)
	check(placed.ok and placed.saved, "Building placement saves in the test village")
	var remaining_wood := g.campaign.state.wood
	await click(button_in(g.village_view, "테스트 종료"))
	check(g.current_screen == "title" and g.campaign == normal, "Exit restores the original campaign controller")
	check(FileAccess.get_file_as_bytes(SAVE) == original, "Construction and exit preserve normal save bytes")
	await click(button_in(g, "마을 바로 테스트"))
	check(g.campaign.active_village_state().count_of_def(&"well") == 1, "Re-entry restores the placed building")
	check(g.campaign.state.wood == remaining_wood, "Re-entry does not refill test resources")
	g.show_title()
	await process_frame
	check(g.campaign == normal and not normal.state.is_liberated(&"ch1_farm"), "Normal game still locked after test session")
	check(not FileAccess.file_exists(SAVE + ".bak"), "Test writes never touch campaign backup")
	# No campaign save is needed to enter. The test slot still works after a fresh start.
	clean(SAVE)
	g.campaign = CampaignController.new(SAVE)
	g.show_title()
	await process_frame
	await process_frame
	await click(button_in(g, "마을 바로 테스트"))
	check(g.current_screen == "village" and not FileAccess.file_exists(SAVE), "Fresh installation enters village without creating campaign progress")
	g.show_title()
	await process_frame
	# A damaged test slot must not silently overwrite either slot.
	var test_store := SaveStore.new(SAVE + Game.VILLAGE_TEST_SUFFIX)
	test_store.delete_all()
	var corrupt := FileAccess.open(test_store.path, FileAccess.WRITE)
	corrupt.store_string("broken test save")
	corrupt.close()
	g.start_village_test()
	await process_frame
	check(g.current_screen == "title" and g.campaign.store.path == SAVE, "Corrupt test save returns to the ordinary title screen")
	check(FileAccess.get_file_as_string(test_store.path) == "broken test save", "Corrupt test save is preserved")
	check(not FileAccess.file_exists(SAVE), "Failure still leaves campaign save absent")
	g.free()
	clean(SAVE)
	finish()

func finish() -> void:
	print("Village entry: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

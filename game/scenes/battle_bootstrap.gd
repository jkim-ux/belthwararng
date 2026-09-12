extends Node
## 장면 안의 HUD와 디버그 표시에 Battle 참조를 연결한다.
func _ready() -> void:
	var battle := get_parent() as Battle
	var hud := battle.get_node_or_null("HUDLayer/HUD")
	if hud != null:
		hud.battle = battle
	var dbg := battle.get_node_or_null("DebugOverlay")
	if dbg != null:
		dbg.battle = battle

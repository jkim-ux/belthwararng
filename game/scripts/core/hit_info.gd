class_name HitInfo
extends RefCounted
## 적중이 확정된 뒤 대상에게 전달하는 정보.
var attacker: Node
var attack: AttackData
var damage: float
var hitstop_ticks: int
var direction: int = 1     ## 밀려나는 방향 (+1 오른쪽)

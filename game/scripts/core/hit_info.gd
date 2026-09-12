class_name HitInfo
extends RefCounted
## 적중이 확정된 뒤 대상에게 전달하는 정보.
## HWR-004: 밀림 거리는 HitBox 단위로 다르게 둘 수 있어(일섬연무 마지막 타만 밀림) knockback 을 따로 싣는다.
## 출처 발 위치·공격 방향은 흘려받기의 정면 판정에, action_id/hit_index/projectile_id 는 처리 키에 쓴다.
var attacker: Node
var attack: AttackData
var damage: float
var hitstop_ticks: int
var direction: int = 1        ## 밀려나는 방향 (+1 오른쪽)
var knockback: float = -1.0   ## 이번 타격의 밀림 총 거리(px). 음수면 attack.knockback 을 쓴다
var hit_index: int = 0        ## 다단히트 순번(일섬연무 0~4, 강인병 2연격 0~1)
var action_id: int = 0        ## 시전 ID(근접). 취소된 시전의 잔여 이벤트 검증용
var projectile_id: int = 0    ## 투사체 인스턴스 ID(투사체 적중일 때)
var source_pos: Vector2 = Vector2.ZERO   ## 공격 출처의 발 위치(근접: 공격자 발, 투사체: 이전 틱 위치)
var attacker_facing: int = 1  ## 공격이 향하는 좌우 방향(근접: 공격자 facing, 투사체: 진행 방향)
var from_projectile: bool = false

func effective_knockback() -> float:
	if knockback >= 0.0:
		return knockback
	return attack.knockback if attack != null else 0.0

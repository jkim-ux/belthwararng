@tool
extends Node3D
## Drag a scene into Godot to use the same geometry as the live village.
@export_enum("tree", "flower_tree", "rock", "fence", "planter", "lantern", "cloud_sign", "basket", "well", "cottage", "greenhouse", "shed", "farm_0", "farm_1", "farm_2", "farm_3", "lumber", "quarry", "road", "repair", "training", "dam", "wheel") var asset_id: String = "tree"
@export_range(0, 2) var variant: int = 0

func _ready() -> void:
	add_child(GardenAssets.make(asset_id, variant))

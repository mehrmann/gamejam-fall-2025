extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Character.energy_updated.connect($Character/Overlay.on_energy_updated.bind())
	$Character.maxDepth_updated.connect($Character/Overlay.on_max_depth_updated.bind())

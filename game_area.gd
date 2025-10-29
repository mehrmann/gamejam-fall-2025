extends StaticBody2D

@onready var boxes = $boxes
var box = preload("res://scenes/box.tscn")
@export var cols := 10
@export var rows := 10
@export var cell_size := 18

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
	spawn_boxes(rows)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_reload_area_body_entered(body: Node2D) -> void:
	$bottom.global_transform=$bottom.global_transform.translated(Vector2(0,18))
	spawn_boxes(1)
	
func spawn_boxes(rows):
	for y in range(rows):
		for x in range(cols):
			var new_box := box.instantiate()
			var local_pos := Vector2(
				x * cell_size,
				y * -cell_size
			)
			# if boxes is a child/sibling under same parent, setting position is enough
			new_box.global_position = $bottom.global_position + local_pos

			# Make bottom row (y=0) unmoveable so it acts as ground
			if y == 0:
				new_box.color = new_box.colors.unmoveable
				new_box.get_node("sprite").animation = "unmoveable"

			boxes.add_child(new_box)	


func _on_kill_zone_body_entered(body: Node2D) -> void:
	body.queue_free()

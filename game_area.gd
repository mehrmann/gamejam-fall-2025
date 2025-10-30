extends StaticBody2D

@onready var boxes = $boxes
var box = preload("res://scenes/box.tscn")
@export var cols := 10
@export var rows := 10
@export var cell_size := 18
@export var gravity_tick_interval := 0.2  # How often to check for falling blocks

var gravity_timer := 0.0
var occupied_cells := {}  # Track which grid cells are occupied
var bottom_row_y := 0  # The current bottom row

func _ready() -> void:
	# Spawn initial static bottom row
	spawn_static_bottom_row()
	# Spawn initial rows above
	spawn_boxes(rows)

func _process(delta: float) -> void:
	# Gravity simulation
	gravity_timer += delta
	if gravity_timer >= gravity_tick_interval:
		gravity_timer = 0.0
		apply_gravity()

func apply_gravity() -> void:
	# Update occupied cells map
	update_occupied_cells()

	# Check each block to see if it can fall
	var blocks = boxes.get_children()
	for block in blocks:
		if block.has_method("fall_one_cell") and can_block_fall(block):
			block.fall_one_cell()

func can_block_fall(block) -> bool:
	if not block or block.is_queued_for_deletion():
		return false
	if block.is_static or block.is_tweening:
		return false

	# Get all grid positions this block occupies (could be a chain)
	var positions = block.get_all_grid_positions()

	# Check if any position below is occupied by a different block
	for pos in positions:
		var below_pos = pos + Vector2i(0, 1)

		# Check if position below is occupied by another block
		if occupied_cells.has(below_pos):
			var block_below = occupied_cells[below_pos]
			# If it's not the same block (in case of merged chains), can't fall
			if block_below != block:
				return false

	return true

func update_occupied_cells() -> void:
	occupied_cells.clear()
	var blocks = boxes.get_children()
	for block in blocks:
		if block and not block.is_queued_for_deletion():
			var positions = block.get_all_grid_positions()
			for pos in positions:
				occupied_cells[pos] = block

func spawn_static_bottom_row() -> void:
	# Spawn a row of static unmoveable blocks at the bottom
	for x in range(cols):
		var new_box := box.instantiate()

		var local_pos := Vector2(
			x * cell_size,
			bottom_row_y * cell_size
		)
		new_box.global_position = $bottom.global_position + local_pos

		boxes.add_child(new_box)

		# Override properties after _ready is called
		new_box.color = 7  # colors.unmoveable
		new_box.is_static = true
		new_box.health = 8
		new_box.get_node("sprite").animation = "unmoveable"

func _on_reload_area_body_entered(body: Node2D) -> void:
	# Move bottom reference down and spawn new row
	$bottom.global_transform = $bottom.global_transform.translated(Vector2(0, cell_size))
	bottom_row_y += 1

	# Spawn new static bottom row
	spawn_static_bottom_row()

	# Spawn new regular row at top
	spawn_boxes(1)

func spawn_boxes(num_rows: int) -> void:
	for y in range(num_rows):
		for x in range(cols):
			var new_box := box.instantiate()
			var local_pos := Vector2(
				x * cell_size,
				(y - num_rows) * cell_size  # Spawn above
			)
			new_box.global_position = $bottom.global_position + local_pos
			boxes.add_child(new_box)

func _on_kill_zone_body_entered(body: Node2D) -> void:
	body.queue_free()

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
	# Spawn initial rows
	spawn_boxes(rows + 1)  # Spawn one extra row for the bottom
	# Convert bottom row to static
	await get_tree().process_frame  # Wait for blocks to initialize
	convert_bottom_row_to_static()

func _process(delta: float) -> void:
	# Gravity simulation
	gravity_timer += delta
	if gravity_timer >= gravity_tick_interval:
		gravity_timer = 0.0
		apply_gravity()
		check_merges()

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

func check_merges() -> void:
	# Check all blocks for possible merges
	var blocks = boxes.get_children()
	for block in blocks:
		if block and not block.is_queued_for_deletion() and block.has_method("check_for_merge"):
			# Only check blocks that are at rest (not falling or tweening)
			if not block.is_tweening and not block.is_falling:
				block.check_for_merge()

func convert_bottom_row_to_static() -> void:
	# Find all blocks at the current bottom row and make them static
	var bottom_y_world = $bottom.global_position.y
	var blocks = boxes.get_children()

	for block in blocks:
		if block and not block.is_queued_for_deletion():
			# Check if block is at the bottom row
			var positions = block.get_all_grid_positions()
			for pos in positions:
				var world_pos = block.cell_to_world(pos)
				if abs(world_pos.y - bottom_y_world) < cell_size / 2:
					# This block is at the bottom row
					block.is_static = true
					block.color = 7  # colors.unmoveable
					block.health = 8
					if block.has_node("sprite"):
						block.get_node("sprite").animation = "unmoveable"
					break

func _on_reload_area_body_entered(body: Node2D) -> void:
	# Move bottom reference down
	$bottom.global_transform = $bottom.global_transform.translated(Vector2(0, cell_size))
	bottom_row_y += 1

	# Convert the new bottom row to static
	convert_bottom_row_to_static()

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

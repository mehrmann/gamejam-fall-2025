extends StaticBody2D

const TILE_SIZE := 18
const FALL_DURATION := 0.15  # Time in seconds for box to fall one tile
const SETTLE_TIME := 0.05  # Time to wait after landing before merging

enum State {
	IDLE,        # Box is stable and not moving
	FALLING,     # Box is currently falling to next position
	SETTLING     # Box just landed, waiting to settle before merging
}

var state := State.IDLE
var target_position := Vector2.ZERO
var fall_progress := 0.0
var settle_timer := 0.0
var can_fall := true  # Whether this merged shape can fall
var being_notified := false  # Recursion guard for cascade notifications

# Signal emitted when this box starts falling (loses support)
signal started_falling

# For backwards compatibility (used by character.gd)
var falling_velocity := 0.0  # Non-zero when falling
var is_resting: bool:
	get: return state == State.IDLE
enum colors {
	red,
	yellow,
	green,
	forest,
	orange,
	steel,
	unbreakable,
	unmoveable
}
@export var color := colors.red
@export var skip_randomize := false  # Set to true to keep manually set color

@onready var sensors : Array[Area2D] = [$sensor_right, $sensor_bottom]
var merge_candidates_map = {}

var health = 1

func _ready() -> void:
	if not skip_randomize:
		randomize_color()
	$sprite.animation = colors.keys()[color]

	# Snap to grid on spawn to ensure proper alignment
	snap_to_grid_position()
	state = State.IDLE

func _physics_process(delta: float) -> void:
	match state:
		State.IDLE:
			_process_idle(delta)
		State.FALLING:
			_process_falling(delta)
		State.SETTLING:
			_process_settling(delta)

func _process_idle(delta: float) -> void:
	# Check if we should start falling
	can_fall = can_shape_fall()

	if can_fall:
		# Calculate where we'll fall to (next grid position below)
		target_position = find_landing_position()
		if target_position != global_position:
			state = State.FALLING
			fall_progress = 0.0
			falling_velocity = TILE_SIZE / FALL_DURATION  # For character collision detection
			started_falling.emit()
			notify_boxes_above()
	else:
		# Not falling - check for merging
		if color < colors.unbreakable:
			for sensor in sensors:
				if sensor != null and sensor.has_overlapping_bodies():
					for overlapping in sensor.get_overlapping_bodies():
						print("Box at ", global_position, " sensor detected overlap with ", overlapping.global_position,
							  " | self.is_resting=", is_resting, " other.is_resting=", overlapping.is_resting,
							  " | self.color=", color, " other.color=", overlapping.color)
						if overlapping.is_resting and overlapping.color == self.color:
							print("  -> MERGING!")
							merge_bodies(self, overlapping, sensor)

func _process_falling(delta: float) -> void:
	# Interpolate towards target position
	fall_progress += delta / FALL_DURATION

	if fall_progress >= 1.0:
		# Reached target
		global_position = target_position
		state = State.SETTLING
		settle_timer = 0.0
		falling_velocity = 0.0
	else:
		# Smooth interpolation
		var start_pos = target_position - Vector2(0, TILE_SIZE)
		global_position = start_pos.lerp(target_position, fall_progress)

func _process_settling(delta: float) -> void:
	# Wait a moment before checking if we need to fall further or merge
	settle_timer += delta

	if settle_timer >= SETTLE_TIME:
		state = State.IDLE

func find_landing_position() -> Vector2:
	# Find the next grid position below where we would land
	# Start from current position and check one tile down at a time
	var current_grid_y = round(global_position.y / TILE_SIZE)
	var grid_x = round(global_position.x / TILE_SIZE) * TILE_SIZE

	# Check each tile below until we find a collision
	var space_state = get_world_2d().direct_space_state

	for tiles_below in range(1, 100):  # Max 100 tiles down
		var check_y = (current_grid_y + tiles_below) * TILE_SIZE
		var test_position = Vector2(grid_x, check_y)

		# Would we collide at this position?
		var would_collide = false
		for child in get_children():
			if child is CollisionShape2D and child.get_parent() == self:
				var offset = child.global_position - global_position
				var query = PhysicsShapeQueryParameters2D.new()
				query.shape = child.shape
				query.transform = Transform2D(0, test_position + offset)
				query.collision_mask = 3
				query.exclude = [self]

				var result = space_state.intersect_shape(query, 1)
				if result.size() > 0:
					would_collide = true
					break

		if would_collide:
			# Can't go to this position - land one tile above
			return Vector2(grid_x, (current_grid_y + tiles_below - 1) * TILE_SIZE)

	# Shouldn't reach here, but return current position if no collision found
	return global_position

func notify_boxes_above() -> void:
	# When we start falling, notify boxes that might be supported by us
	# Check the tile immediately above each of our collision shapes
	var space_state = get_world_2d().direct_space_state
	var notified_boxes := {}  # Track which boxes we've already notified to avoid duplicates

	for child in get_children():
		if child is CollisionShape2D and child.get_parent() == self:
			var tile_cell = world_to_cell(child.global_position)
			var above_cell = tile_cell + Vector2i(0, -1)
			var check_position = Vector2(above_cell.x * TILE_SIZE, above_cell.y * TILE_SIZE)

			var query = PhysicsShapeQueryParameters2D.new()
			query.shape = child.shape
			query.transform = Transform2D(0, check_position)
			query.collision_mask = 2  # Only detect boxes (layer 2) above us
			query.exclude = [self]

			var results = space_state.intersect_shape(query, 10)

			for result in results:
				var other_body = result["collider"]
				# If it's another box, tell it to re-check
				# Only notify each box once to avoid redundant checks
				if other_body is StaticBody2D and other_body.has_method("force_fall_check"):
					if not notified_boxes.has(other_body):
						notified_boxes[other_body] = true
						other_body.force_fall_check()

func force_fall_check() -> void:
	# Called by boxes below us when they start falling
	# Force immediate re-evaluation of our fall state
	#
	# Multiple guards against infinite recursion:
	# 1. Only process if currently idle (not already falling)
	# 2. being_notified flag prevents re-entry during cascade

	if state != State.IDLE or being_notified:
		return

	# Set guard before any recursive calls
	being_notified = true

	can_fall = can_shape_fall()
	if can_fall:
		# We should also start falling!
		target_position = find_landing_position()
		if target_position != global_position:
			state = State.FALLING
			fall_progress = 0.0
			falling_velocity = TILE_SIZE / FALL_DURATION
			started_falling.emit()
			# Recursively notify boxes above us
			notify_boxes_above()

	# Clear guard after cascade completes
	being_notified = false

func can_shape_fall() -> bool:
	# Determines if this merged shape can fall by checking all bottom tiles
	# Use direct position checks instead of physics queries for reliability

	# Find all bottom tiles
	var occ = build_occupancy()
	var bottom_tiles: Array[CollisionShape2D] = []

	for child in get_children():
		if not (child is CollisionShape2D):
			continue
		if child.get_parent() != self:
			continue

		var cell = world_to_cell(child.global_position)
		var below_cell = cell + Vector2i(0, 1)

		# If there's no tile directly below this one in our merged shape, it's a bottom tile
		if not occ.has(below_cell):
			bottom_tiles.append(child)

	# If no bottom tiles found, don't fall
	if bottom_tiles.is_empty():
		print("Box at ", global_position, " has no bottom tiles, won't fall")
		return false

	# Check if ALL bottom tiles have the immediate tile below them free
	# Use get_tree() to check all boxes directly instead of physics queries
	var all_boxes = get_tree().get_nodes_in_group("block")

	for tile in bottom_tiles:
		var tile_cell = world_to_cell(tile.global_position)
		var below_cell = tile_cell + Vector2i(0, 1)

		# Check all other boxes to see if any occupy the cell below
		for other_box in all_boxes:
			if other_box == self:
				continue
			if other_box.is_queued_for_deletion():
				continue

			# For merged boxes, check all their collision shapes
			var other_occ = other_box.build_occupancy() if other_box.has_method("build_occupancy") else {}

			if other_occ.has(below_cell):
				# This box has a tile at the position below us
				# Only consider it support if it's stable (IDLE state)
				if other_box.has_method("get"):
					var other_state = other_box.get("state")
					if other_state == State.IDLE:
						print("Box at ", global_position, " (color ", color, ") blocked by IDLE box at cell ", below_cell)
						return false  # Has stable support
					else:
						print("Box at ", global_position, " found FALLING/SETTLING box at ", below_cell, ", ignoring")
				else:
					# Not a box (shouldn't happen with "block" group)
					print("Box at ", global_position, " blocked by non-box at cell ", below_cell)
					return false

	# All bottom tiles are free below
	print("Box at ", global_position, " (color ", color, ") CAN FALL")
	return true

func snap_to_grid_position() -> void:
	# Snap to nearest grid position (used on spawn)
	var grid_x = round(global_position.x / TILE_SIZE) * TILE_SIZE
	var grid_y = round(global_position.y / TILE_SIZE) * TILE_SIZE
	global_position = Vector2(grid_x, grid_y)

func merge_bodies(host: StaticBody2D, guest: StaticBody2D, sensor: Area2D):
	if host == guest or host.is_queued_for_deletion() or guest.is_queued_for_deletion():
		return

	# Reset velocities
	host.falling_velocity = 0.0
	host.rest_timer = 0.0

	for child in guest.get_children():
		var oldName = child.name
		child.reparent(host, true)
		child.name = guest.name + "_" + oldName
		if child is Area2D:
			sensors.append(child)
			#child.body_entered.connect(on_sensor_body_entered.bind(child))
			#child.body_exited.connect(on_sensor_body_exited.bind(child))
		
	#print_tree_pretty()
	sensors.erase(sensor)
	sensor.queue_free()
	guest.queue_free()
	
	var occ = build_occupancy()
	for collisionShape in get_children().filter(func(node: Node2D): return node is CollisionShape2D):
		var neighbor_mask = get_neighbors_for(collisionShape, occ)
		#print(collisionShape.name + "=" + str(neighbor_mask))
		(get_node(collisionShape.name.replace("collisionshape", "sprite")) as AnimatedSprite2D).frame = neighbor_mask

func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(
		floor(p.x / TILE_SIZE),
		floor(p.y / TILE_SIZE)
	)
	
func build_occupancy() -> Dictionary:
	var occ := {}
	for child in get_children():
		if child is CollisionShape2D:
			# Only count collision shapes that are direct children (not sensor children)
			# Sensor collision shapes are children of Area2D nodes
			if child.get_parent() == self:
				var cell := world_to_cell(child.global_position)
				occ[cell] = child
	return occ

func get_neighbors_for(child: CollisionShape2D, occ: Dictionary) -> int:
	var cell := world_to_cell(child.global_position)
	
	const DIRS := {
		Vector2i(-1, 0): 1,  # left  -> bit 0
		Vector2i(1, 0): 2,   # right -> bit 1
		Vector2i(0, -1): 4,  # up    -> bit 2
		Vector2i(0, 1): 8    # down  -> bit 3
	}
	
	var mask := 0
	for dir in DIRS:
		if occ.has(cell + dir):
			mask |= DIRS[dir]
			
	return mask

func randomize_color():
	var max_colors = 2
	var unbreakable = 0.05
	if (global_position.y > 100 * 18):
		max_colors = 6
		unbreakable = 0.1
	elif (global_position.y > 80 * 18):
		max_colors = 5
		unbreakable = 0.15
	elif (global_position.y > 60 * 18):
		max_colors = 4
		unbreakable = 0.2
	elif (global_position.y > 20*18):
		max_colors = 3
		unbreakable = 0.3
	var keys := colors.keys()
	if randf() > unbreakable:
		color = colors[keys[randi() % max_colors]]
	else:
		health = 8
		if randf() > 0.5:
			color = colors.unbreakable
		else:
			color = colors.unmoveable

func snap_to_grid(world_pos: Vector2, grid_origin: Vector2, cell_size: float) -> Vector2:
	var local_pos = world_pos - grid_origin
	var cell_x = round(local_pos.x / cell_size)
	var cell_y = round(local_pos.y / cell_size)
	return grid_origin + Vector2(cell_x * cell_size, cell_y * cell_size)

extends StaticBody2D

const GRAVITY = 500.0  # Pixels per second squared
const MAX_FALL_SPEED = 400.0  # Maximum falling speed
const STOP_SPEED_THRESHOLD = 5.0  # Speed threshold to consider stopped
const REST_TIME_REQUIRED = 0.1  # Time required to be considered resting
const TILE_SIZE := 18
const FALL_CHECK_DISTANCE := 10.0  # How far below to check for support (larger for more reliable detection)

var rest_timer := 0.0
@export var is_resting := false
var falling_velocity := 0.0  # Custom velocity for fake physics
var last_position := Vector2.ZERO
var can_fall := true  # Whether this merged shape can fall
var being_notified := false  # Recursion guard for cascade notifications

# Signal emitted when this box starts falling (loses support)
signal started_falling
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

@onready var sensors : Array[Area2D] = [$sensor_right, $sensor_bottom]
var merge_candidates_map = {}

var health = 1

func _ready() -> void:
	randomize_color()
	$sprite.animation = colors.keys()[color]

	# Snap to grid on spawn to ensure proper alignment
	snap_to_grid_position()
	last_position = global_position

func _physics_process(delta: float) -> void:
	# Update resting state first so other boxes can check it reliably
	# This must happen before can_shape_fall() is called by other boxes
	is_resting = rest_timer >= REST_TIME_REQUIRED

	# Check if this merged shape can fall by checking all bottom tiles
	# This needs to be checked every frame as conditions can change
	var previous_can_fall = can_fall
	can_fall = can_shape_fall()

	# If we just started falling, reset velocity accumulation and notify other boxes
	if can_fall and not previous_can_fall:
		falling_velocity = 0.0
		rest_timer = 0.0
		is_resting = false  # Immediately mark as not resting
		started_falling.emit()
		# Trigger re-evaluation for all other resting boxes in case they were supported by us
		notify_boxes_above()

	# Apply custom fake physics (gravity)
	if not is_resting and can_fall:
		falling_velocity += GRAVITY * delta
		falling_velocity = min(falling_velocity, MAX_FALL_SPEED)

		# Calculate movement for this frame
		var movement = Vector2(0, falling_velocity * delta)

		# Check for collision using physics query
		var space_state = get_world_2d().direct_space_state
		var collision_detected = false

		# Test movement for all collision shapes
		for child in get_children():
			if child is CollisionShape2D:
				var query = PhysicsShapeQueryParameters2D.new()
				query.shape = child.shape
				query.transform = Transform2D(0, child.global_position + movement)
				# Detect both ground (layer 1) AND boxes (layer 2) for collision detection
				# This is separate from the body's collision_mask which only affects physics response
				query.collision_mask = 3
				query.exclude = [self]

				var result = space_state.intersect_shape(query, 1)
				if result.size() > 0:
					collision_detected = true
					break

		if collision_detected:
			# Hit something, snap to grid position ABOVE (floor y to avoid snapping through)
			snap_to_grid_position_above()
			falling_velocity = 0
			rest_timer = 0.0
		else:
			# Move the box
			global_position += movement
			rest_timer = 0.0
	else:
		# Not falling, increase rest timer
		if falling_velocity < STOP_SPEED_THRESHOLD:
			rest_timer += delta
		else:
			rest_timer = 0.0

		if rest_timer >= REST_TIME_REQUIRED:
			falling_velocity = 0

	is_resting = rest_timer >= REST_TIME_REQUIRED
	last_position = global_position

	# Handle merging
	if is_resting and color < colors.unbreakable:
		for sensor in sensors:
			if sensor != null and sensor.has_overlapping_bodies():
				for overlapping in sensor.get_overlapping_bodies():
					if overlapping.is_resting and overlapping.color == self.color:
						merge_bodies(self, overlapping, sensor)

func notify_boxes_above() -> void:
	# When we start falling, notify boxes that might be supported by us
	# Check above each of our collision shapes for other boxes
	var space_state = get_world_2d().direct_space_state
	var notified_boxes := {}  # Track which boxes we've already notified to avoid duplicates

	for child in get_children():
		if child is CollisionShape2D:
			var query = PhysicsShapeQueryParameters2D.new()
			query.shape = child.shape
			# Check slightly above this tile
			query.transform = Transform2D(0, child.global_position + Vector2(0, -FALL_CHECK_DISTANCE))
			query.collision_mask = 2  # Only detect boxes (layer 2) above us
			query.exclude = [self]

			var results = space_state.intersect_shape(query, 10)

			for result in results:
				var other_body = result["collider"]
				# If it's another box that's resting, tell it to re-check
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
	# 1. Only process if currently resting (not already falling)
	# 2. being_notified flag prevents re-entry during cascade

	if not is_resting or being_notified:
		return

	# Set guard before any recursive calls
	being_notified = true

	can_fall = can_shape_fall()
	if can_fall:
		# We should also start falling!
		falling_velocity = 0.0
		rest_timer = 0.0
		is_resting = false
		started_falling.emit()
		# Recursively notify boxes above us
		notify_boxes_above()

	# Clear guard after cascade completes
	being_notified = false

func can_shape_fall() -> bool:
	# Determines if this merged shape can fall by checking all bottom tiles
	#
	# For merged shapes (L-shapes, T-shapes, etc.), the shape can only fall when
	# ALL of its bottom tiles are unsupported. A tile is considered supported if:
	# 1. There's solid ground below it
	# 2. There's a RESTING box below it (not falling or unstable)
	#
	# Cascading behavior:
	# When support is removed from a tower of boxes, they start falling immediately.
	# This is handled via the notify_boxes_above() system:
	#
	# Example: Tower of 3 boxes loses bottom support
	# 1. Bottom box detects no support, starts falling
	# 2. Bottom box calls notify_boxes_above()
	# 3. Middle box receives force_fall_check(), re-evaluates, starts falling
	# 4. Middle box calls notify_boxes_above()
	# 5. Top box receives force_fall_check(), re-evaluates, starts falling
	#
	# This entire cascade happens in a single frame via recursive notification,
	# so all boxes in a tower start falling simultaneously when support is removed.
	#
	# Infinite recursion protection:
	# Even with complex interlocking shapes (C-shapes, circular dependencies, etc.),
	# infinite recursion is prevented by:
	# 1. is_resting check - once a box starts falling, it won't process again
	# 2. being_notified flag - prevents re-entry during cascade propagation
	# 3. notified_boxes dict - each box is only notified once per cascade
	#
	# Example with circular dependency:
	# Box A (supports Box B) loses support → A.is_resting=false, being_notified=true
	# → notifies Box B → B checks, starts falling → B.is_resting=false
	# → B tries to notify A → A.force_fall_check() sees being_notified=true → returns
	# Result: Safe, no infinite recursion

	# Find all bottom tiles (tiles that don't have another tile directly below them)
	var occ = build_occupancy()
	var bottom_tiles: Array[CollisionShape2D] = []

	for child in get_children():
		if child is CollisionShape2D:
			var cell = world_to_cell(child.global_position)
			var below_cell = cell + Vector2i(0, 1)

			# If there's no tile directly below this one in our merged shape, it's a bottom tile
			if not occ.has(below_cell):
				bottom_tiles.append(child)

	# If no bottom tiles found, something is wrong - don't fall
	if bottom_tiles.is_empty():
		return false

	# Check if ALL bottom tiles have no support below them
	var space_state = get_world_2d().direct_space_state

	for tile in bottom_tiles:
		# Check for solid ground or other boxes below this tile
		var query = PhysicsShapeQueryParameters2D.new()
		query.shape = tile.shape
		query.transform = Transform2D(0, tile.global_position + Vector2(0, FALL_CHECK_DISTANCE))
		query.collision_mask = 3  # Detect both ground (layer 1) and boxes (layer 2)
		query.exclude = [self]

		var results = space_state.intersect_shape(query, 10)

		for result in results:
			var other_body = result["collider"]

			# Check if there's a box or solid ground below
			if other_body is StaticBody2D:
				# Check if it's another box that's also falling
				if other_body.has_method("get") and other_body.get("falling_velocity") != null:
					# It's a box - only consider it support if it's truly stable
					# Check multiple stability indicators to avoid evaluation order issues
					var other_falling_velocity = other_body.get("falling_velocity")
					var other_is_resting = other_body.get("is_resting")

					# A box is stable support if:
					# 1. It has very low/no falling velocity, AND
					# 2. It's in a resting state (has been stable for REST_TIME_REQUIRED)
					if abs(other_falling_velocity) < STOP_SPEED_THRESHOLD and other_is_resting:
						# Box below is truly stable, we have support
						return false
					# Otherwise, box below is falling or unstable, continue checking other tiles
				else:
					# It's solid ground (not a box), we have support
					return false
			elif other_body is TileMap or other_body is CharacterBody2D:
				# Ground or player provides support
				return false

	# All bottom tiles are unsupported, we can fall
	return true

func snap_to_grid_position() -> void:
	# Snap to nearest grid position (used on spawn)
	var grid_x = round(global_position.x / TILE_SIZE) * TILE_SIZE
	var grid_y = round(global_position.y / TILE_SIZE) * TILE_SIZE
	global_position = Vector2(grid_x, grid_y)

func snap_to_grid_position_above() -> void:
	# Snap to grid position above current position (used when landing from fall)
	# Uses floor() to ensure we snap UP, not down through the object we collided with
	var grid_x = round(global_position.x / TILE_SIZE) * TILE_SIZE
	var grid_y = floor(global_position.y / TILE_SIZE) * TILE_SIZE
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

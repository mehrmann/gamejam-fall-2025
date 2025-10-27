extends StaticBody2D

const GRAVITY = 500.0  # Pixels per second squared
const MAX_FALL_SPEED = 400.0  # Maximum falling speed
const STOP_SPEED_THRESHOLD = 5.0  # Speed threshold to consider stopped
const REST_TIME_REQUIRED = 0.1  # Time required to be considered resting
const TILE_SIZE := 18
const FALL_CHECK_DISTANCE := 2.0  # How far below to check for support

var rest_timer := 0.0
@export var is_resting := false
var falling_velocity := 0.0  # Custom velocity for fake physics
var last_position := Vector2.ZERO
var can_fall := true  # Whether this merged shape can fall
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
	last_position = global_position

func _physics_process(delta: float) -> void:
	# Check if this merged shape can fall by checking all bottom tiles
	can_fall = can_shape_fall()

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
				query.collision_mask = collision_mask
				query.exclude = [self]

				var result = space_state.intersect_shape(query, 1)
				if result.size() > 0:
					collision_detected = true
					break

		if collision_detected:
			# Hit something, snap to grid and stop
			snap_to_grid_position()
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

func can_shape_fall() -> bool:
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
		query.collision_mask = collision_mask
		query.exclude = [self]

		var results = space_state.intersect_shape(query, 10)

		for result in results:
			var other_body = result["collider"]

			# Check if there's a box or solid ground below
			if other_body is StaticBody2D:
				# Check if it's another box that's also falling
				if other_body.has_method("get") and other_body.get("falling_velocity") != null:
					# It's a box - only consider it support if it's not falling
					var other_falling_velocity = other_body.get("falling_velocity")
					var other_can_fall = other_body.get("can_fall")

					if abs(other_falling_velocity) < STOP_SPEED_THRESHOLD and not other_can_fall:
						# Box below is stable, we have support
						return false
				else:
					# It's solid ground (not a box), we have support
					return false
			elif other_body is TileMap or other_body is CharacterBody2D:
				# Ground or player provides support
				return false

	# All bottom tiles are unsupported, we can fall
	return true

func snap_to_grid_position() -> void:
	# Snap to nearest grid position
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

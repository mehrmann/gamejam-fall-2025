extends CharacterBody2D

const GRAVITY = 500.0  # Pixels per second squared
const MAX_FALL_SPEED = 400.0  # Maximum falling speed
const STOP_SPEED_THRESHOLD = 5.0  # Speed threshold to consider stopped
const REST_TIME_REQUIRED = 0.1  # Time required to be considered resting
const TILE_SIZE := 18

var rest_timer := 0.0
@export var is_resting := false
var falling_velocity := 0.0  # Custom velocity for fake physics
var last_position := Vector2.ZERO
var moved_this_frame := false
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
	# Apply custom fake physics (gravity)
	if not is_resting:
		falling_velocity += GRAVITY * delta
		falling_velocity = min(falling_velocity, MAX_FALL_SPEED)

		# Set velocity for CharacterBody2D
		velocity.y = falling_velocity
		velocity.x = 0  # No horizontal movement

		# Move and check for collision
		var collision = move_and_collide(velocity * delta)

		if collision:
			# Hit something, snap to grid and stop
			snap_to_grid_position()
			falling_velocity = 0
			velocity = Vector2.ZERO
			rest_timer = 0.0
		else:
			# Check if we actually moved
			var distance_moved = global_position.distance_to(last_position)
			if distance_moved < STOP_SPEED_THRESHOLD * delta:
				rest_timer += delta
			else:
				rest_timer = 0.0

	# Update resting state
	if falling_velocity < STOP_SPEED_THRESHOLD:
		rest_timer += delta
	else:
		rest_timer = 0.0

	is_resting = rest_timer >= REST_TIME_REQUIRED
	last_position = global_position

	# Handle merging
	if is_resting and color < colors.unbreakable:
		for sensor in sensors:
			if sensor != null and sensor.has_overlapping_bodies():
				for overlapping in sensor.get_overlapping_bodies():
					if overlapping.is_resting and overlapping.color == self.color:
						merge_bodies(self, overlapping, sensor)

func snap_to_grid_position() -> void:
	# Snap to nearest grid position
	var grid_x = round(global_position.x / TILE_SIZE) * TILE_SIZE
	var grid_y = round(global_position.y / TILE_SIZE) * TILE_SIZE
	global_position = Vector2(grid_x, grid_y)

func merge_bodies(host: CharacterBody2D, guest: CharacterBody2D, sensor: Area2D):
	if host == guest or host.is_queued_for_deletion() or guest.is_queued_for_deletion():
		return

	# Reset velocities
	host.falling_velocity = 0.0
	host.velocity = Vector2.ZERO

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

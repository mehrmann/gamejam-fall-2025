extends RigidBody2D

const STOP_SPEED_THRESHOLD = 5.0
const REST_TIME_REQUIRED = 0.3
const TILE_SIZE := 18  

var rest_timer := 0.0
@export var is_resting := false
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

func _physics_process(delta: float) -> void:
	if linear_velocity.length() < STOP_SPEED_THRESHOLD:
		rest_timer += delta
	else:
		rest_timer = 0.0

	var was_resting = is_resting
	is_resting = rest_timer >= REST_TIME_REQUIRED

	# Snap to grid when first coming to rest
	if is_resting and not was_resting:
		call_deferred("snap_to_grid")

	if is_resting and color == colors.unmoveable:
		freeze = true
		can_sleep = true

	if is_resting and color < colors.unbreakable:
		for sensor in sensors:
			if sensor != null and sensor.has_overlapping_bodies():
				for overlapping in sensor.get_overlapping_bodies():
					if overlapping.is_resting and overlapping.color == self.color:
						merge_bodies(self, overlapping, sensor)

func merge_bodies(host: RigidBody2D, guest: RigidBody2D, sensor: Area2D):
	if host == guest or host.is_queued_for_deletion() or guest.is_queued_for_deletion():
		return

	# Stop all movement for stable merging
	host.linear_velocity = Vector2.ZERO
	guest.linear_velocity = Vector2.ZERO

	# Add mass from guest to host
	host.mass += guest.mass

	# Transfer all children from guest to host
	for child in guest.get_children():
		var oldName = child.name
		child.reparent(host, true)
		child.name = guest.name + "_" + oldName
		if child is Area2D:
			sensors.append(child)

	# Remove the merged sensor
	sensors.erase(sensor)
	sensor.call_deferred("queue_free")
	guest.call_deferred("queue_free")

	# Snap everything to grid after merge for proper alignment
	call_deferred("snap_to_grid")
	call_deferred("update_sprite_frames")

func update_sprite_frames() -> void:
	# Update all sprite frames based on neighbor occupancy
	var occ = build_occupancy()
	for collisionShape in get_children().filter(func(node: Node2D): return node is CollisionShape2D):
		var neighbor_mask = get_neighbors_for(collisionShape, occ)
		var sprite_name = collisionShape.name.replace("collisionshape", "sprite")
		if has_node(sprite_name):
			(get_node(sprite_name) as AnimatedSprite2D).frame = neighbor_mask

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

func snap_to_grid() -> void:
	# Snap the body's position to the nearest grid point
	var snapped_x = round(global_position.x / TILE_SIZE) * TILE_SIZE
	var snapped_y = round(global_position.y / TILE_SIZE) * TILE_SIZE
	global_position = Vector2(snapped_x, snapped_y)

	# Also snap all child collision shapes and sprites to maintain grid alignment
	for child in get_children():
		if child is CollisionShape2D or child is AnimatedSprite2D:
			var local_snapped_x = round(child.position.x / TILE_SIZE) * TILE_SIZE
			var local_snapped_y = round(child.position.y / TILE_SIZE) * TILE_SIZE
			child.position = Vector2(local_snapped_x, local_snapped_y)

extends StaticBody2D

const TILE_SIZE := 18
const FALL_DURATION := 0.15  # Time to tween from one grid cell to next

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
@export var is_falling := false
@export var is_static := false  # For unmoveable blocks at the bottom

@onready var sensors : Array[Area2D] = [$sensor_right, $sensor_bottom]
var health = 1
var grid_position := Vector2i.ZERO  # Current grid position
var is_tweening := false

func _ready() -> void:
	randomize_color()
	$sprite.animation = colors.keys()[color]
	# Calculate initial grid position
	grid_position = world_to_cell(global_position)

	# Static blocks don't fall
	if color == colors.unmoveable:
		is_static = true

func set_grid_position(pos: Vector2i) -> void:
	grid_position = pos
	global_position = cell_to_world(pos)

func cell_to_world(cell: Vector2i) -> Vector2:
	# Convert grid cell to world position
	return Vector2(cell.x * TILE_SIZE, cell.y * TILE_SIZE)

func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(
		roundi(p.x / TILE_SIZE),
		roundi(p.y / TILE_SIZE)
	)

func fall_one_cell() -> void:
	if is_tweening or is_static:
		return

	is_tweening = true
	is_falling = true

	var target_grid_pos = grid_position + Vector2i(0, 1)
	var target_world_pos = cell_to_world(target_grid_pos)

	# Create tween for smooth movement
	var tween = create_tween()
	tween.tween_property(self, "global_position", target_world_pos, FALL_DURATION)
	tween.finished.connect(_on_fall_complete.bind(target_grid_pos))

func _on_fall_complete(new_grid_pos: Vector2i) -> void:
	grid_position = new_grid_pos
	is_tweening = false
	is_falling = false
	# Trigger merge check when we stop falling
	check_for_merge()

func check_for_merge() -> void:
	if is_static or color >= colors.unbreakable:
		return

	for sensor in sensors:
		if sensor != null and sensor.has_overlapping_bodies():
			for overlapping in sensor.get_overlapping_bodies():
				if overlapping.has_method("can_merge_with") and overlapping.can_merge_with(self):
					merge_bodies(self, overlapping, sensor)
					return

func can_merge_with(other) -> bool:
	if not other or other == self:
		return false
	if is_tweening or is_falling or is_static:
		return false
	if other.has("is_tweening") and (other.is_tweening or other.is_falling):
		return false
	if other.has("color") and other.color == self.color and color < colors.unbreakable:
		return true
	return false

func merge_bodies(host: StaticBody2D, guest: StaticBody2D, sensor: Area2D):
	if host == guest or host.is_queued_for_deletion() or guest.is_queued_for_deletion():
		return

	# Transfer all children from guest to host
	for child in guest.get_children():
		var oldName = child.name
		child.reparent(host, true)
		child.name = guest.name + "_" + oldName
		if child is Area2D:
			sensors.append(child)

	# Remove the sensor that detected the overlap
	sensors.erase(sensor)
	sensor.queue_free()
	guest.queue_free()

	# Update sprite frames based on neighbors
	var occ = build_occupancy()
	for collisionShape in get_children().filter(func(node: Node2D): return node is CollisionShape2D):
		var neighbor_mask = get_neighbors_for(collisionShape, occ)
		(get_node(collisionShape.name.replace("collisionshape", "sprite")) as AnimatedSprite2D).frame = neighbor_mask

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
			is_static = true

func get_all_grid_positions() -> Array[Vector2i]:
	# Returns all grid positions occupied by this block (including merged blocks)
	var positions: Array[Vector2i] = []
	for child in get_children():
		if child is CollisionShape2D:
			var cell := world_to_cell(child.global_position)
			positions.append(cell)
	return positions

func snap_to_grid(world_pos: Vector2, grid_origin: Vector2, cell_size: float) -> Vector2:
	var local_pos = world_pos - grid_origin
	var cell_x = round(local_pos.x / cell_size)
	var cell_y = round(local_pos.y / cell_size)
	return grid_origin + Vector2(cell_x * cell_size, cell_y * cell_size)

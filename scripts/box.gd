extends RigidBody2D

const STOP_SPEED_THRESHOLD = 5.0
const REST_TIME_REQUIRED = 0.25
const TILE_SIZE := 18  

var rest_timer := 0.0
@export var is_resting := false
@export var color := "blue"

@onready var sensors : Array[Area2D] = [$sensor_right, $sensor_bottom]
var merge_candidates_map = {}

func _ready() -> void:
	for sensor in sensors:
		sensor.body_entered.connect(on_sensor_body_entered.bind(sensor))
		sensor.body_exited.connect(on_sensor_body_exited.bind(sensor))

func _physics_process(delta: float) -> void:
	if linear_velocity.length() < STOP_SPEED_THRESHOLD:
		rest_timer += delta
	else:
		rest_timer = 0.0
	
	is_resting = rest_timer >= REST_TIME_REQUIRED
	
	if is_resting:
		for sensor in merge_candidates_map:
			var candidate = merge_candidates_map[sensor]
			print("merge candidate " + candidate.name)
			if candidate.is_resting:
				merge_bodies(self, candidate, sensor)
				merge_candidates_map.erase(sensor)

func on_sensor_body_entered(body: Node2D, sensor: Area2D) -> void:
	if body is RigidBody2D:
		merge_candidates_map[sensor] = body

func on_sensor_body_exited(body: Node2D, sensor: Area2D) -> void:
	if merge_candidates_map.has(sensor) and body == merge_candidates_map[sensor]:
		merge_candidates_map.erase(sensor)

func merge_bodies(host: RigidBody2D, guest: RigidBody2D, sensor: Area2D):
	if host == guest or host.is_queued_for_deletion() or guest.is_queued_for_deletion():
		return

	host.mass += guest.mass

	host.linear_velocity = Vector2.ZERO
	#host.angular_velocity = 0.0

	print("merging " + host.name + " and " + guest.name)
	for child in guest.get_children():
		var oldName = child.name
		child.reparent(host, true)
		child.name = guest.name + "_" + oldName
		if child is Area2D:
			child.body_entered.connect(on_sensor_body_entered.bind(child))
			child.body_exited.connect(on_sensor_body_exited.bind(child))
		
	print_tree_pretty()
	
	sensor.queue_free()
	guest.queue_free()
	
	var occ = build_occupancy()
	for collisionShape in get_children().filter(func(node: Node2D): return node is CollisionShape2D):
		print(str(collisionShape) + str(get_neighbors_for(collisionShape, occ)))

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

func get_neighbors_for(child: CollisionShape2D, occ: Dictionary) -> Dictionary:
	var cell := world_to_cell(child.global_position)
	return {
		"left":  occ.has(cell + Vector2i(-1, 0)),
		"right": occ.has(cell + Vector2i(1, 0)),
		"up":    occ.has(cell + Vector2i(0, -1)),
		"down":  occ.has(cell + Vector2i(0, 1)),
	}
	

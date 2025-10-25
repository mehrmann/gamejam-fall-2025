extends RigidBody2D

const STOP_SPEED_THRESHOLD = 5.0
const REST_TIME_REQUIRED = 0.25

var rest_timer := 0.0
@export var is_resting := false
@export var color := "blue"

var candidate_right: RigidBody2D = null
var candidate_bottom: RigidBody2D = null

func _physics_process(delta: float) -> void:
	if linear_velocity.length() < STOP_SPEED_THRESHOLD:
		rest_timer += delta
	else:
		rest_timer = 0.0
	
	is_resting = rest_timer >= REST_TIME_REQUIRED
	
	if is_resting:
		if candidate_right:
			if candidate_right.is_resting:
				pass
				#print("merge bodies (right): " + name + " and " + candidate_right.name)
		if candidate_bottom:
			if candidate_bottom.is_resting:
				pass
				#print("merge bodies (bottom): " + name + " and " + candidate_bottom.name)

func _on_sensor_bottom_body_entered(body: Node2D) -> void:
	if body is RigidBody2D:
		candidate_bottom = body

func _on_sensor_bottom_body_exited(body: Node2D) -> void:
	if body == candidate_bottom:
		candidate_bottom = null

func _on_sensor_right_body_entered(body: Node2D) -> void:
	if body is RigidBody2D:
		candidate_right = body

func _on_sensor_right_body_exited(body: Node2D) -> void:
	if body == candidate_bottom:
		candidate_right = null

#func merge_bodies(host: RigidBody2D, guest: RigidBody2D):
	#host.mass += guest.mass
	#
	#host.linear_velocity = Vector2.ZERO
	#host.angular_velocity = 0.0
	#
	#for child in guest.get_children():
		#var old_glov

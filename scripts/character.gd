extends CharacterBody2D

const SPEED = 150.0
const JUMP_VELOCITY = -180.0
@onready var sprite = $sprite
@onready var left_tool = $left_tool
@onready var right_tool = $right_tool
@onready var bottom_tool = $bottom_tool
@onready var bodyShape = $body
@onready var audio_player = $AudioStreamPlayer2D
var break_block_sound = preload("res://assets/sounds/break_block.wav")
var splat_sound = preload("res://assets/sounds/splat.wav")

func _physics_process(delta:float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		sprite.flip_h = direction < 0
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
	
	if Input.is_action_just_pressed("drill"):
		if Input.is_action_pressed("ui_down"):
			for body in bottom_tool.get_overlapping_bodies():
				break_block(body)
		elif !sprite.flip_h:
			for body in right_tool.get_overlapping_bodies():
				break_block(body)
		else:
			for body in left_tool.get_overlapping_bodies():
				break_block(body)

	move_and_slide()


func _on_head_body_entered(body: Node2D) -> void:
	if body is RigidBody2D:
		var block = body as RigidBody2D
		if block.linear_velocity.abs().y > 0:
			audio_player.stream = splat_sound
			audio_player.play()

func break_block(body):
	audio_player.stream = break_block_sound
	audio_player.play()
	body.queue_free()

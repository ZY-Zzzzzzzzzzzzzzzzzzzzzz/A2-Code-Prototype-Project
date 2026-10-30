extends Area3D
# This is a memory shard. It only exists on the lower floor, in the dark.
# It glows by itself, spins, and floats up and down.
# If the player touches it  -> it is collected (+1 score).
# If the monster touches it -> it is eaten and gone forever.
# It also has an "echo" sound: when the player presses Q,
# this shard answers after some seconds (later = farther away).


# ================== settings (you can change these) ==================
const SPIN_SPEED := 2.0     # spin speed
const FLOAT_SPEED := 2.0    # how fast it floats up and down
const FLOAT_RANGE := 0.3    # how far it floats up and down (meters)
const HOVER_HEIGHT := 0.9   # the middle height of the floating

signal collected   # "the player got me" - game.gd counts the score
signal eaten       # "the monster ate me" - game.gd makes the total smaller

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var _echo: AudioStreamPlayer3D = $Echo

var _time := 0.0   # my own clock, used for the floating


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_time = randf() * TAU   # random start time, so all shards float differently


func _process(delta: float) -> void:
	_time += delta
	rotate_y(SPIN_SPEED * delta)   # spin around
	# sin goes from -1 to 1, so the shard moves up and down around its height
	mesh.position.y = HOVER_HEIGHT + sin(_time * FLOAT_SPEED) * FLOAT_RANGE


# something walked into me. Who was it?
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_collected()
	elif body.is_in_group("monster"):
		_eaten()


# the player pressed Q: play my echo after "delay" seconds
func play_echo(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_inside_tree():   # maybe I was already picked up while waiting
		_echo.play()


func _collected() -> void:
	collected.emit()
	_disappear(0.2)


func _eaten() -> void:
	eaten.emit()
	_disappear(0.35)   # being eaten looks a little slower, like a small fight


func _disappear(duration: float) -> void:
	# stop the touch detection, so it cannot happen twice
	# set_deferred = "do it at the end of this frame" (Godot asks for this here)
	set_deferred("monitoring", false)
	var tween := create_tween()
	tween.tween_property(mesh, "scale", Vector3.ONE * 0.01, duration)   # shrink to nothing
	tween.tween_callback(queue_free)                                     # then delete me

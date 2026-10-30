extends CharacterBody3D
# This is the player.
# It can move, jump, look around, switch floors (F) and listen (Q).


# ================== settings (you can change these) ==================
const SPEED = 5.0                  # walk speed (meters per second)
const JUMP_VELOCITY = 4.5          # how strong the jump is
const MOUSE_SENSITIVITY = 0.0025   # how fast the mouse turns the view

# ---- the height of the two floors ----
const UPPER_FLOOR_Y = 4.0    # player y when standing on the upper floor
const LOWER_FLOOR_Y = -1.0   # player y when standing on the lower floor
const FLOOR_THRESHOLD = 2.0  # player y above this line = upper floor

# the light of the lower floor: almost black (numbers from 0 to 1)
const DEEP_AMBIENT := Color(0.015, 0.015, 0.02)

const FADE_IN_TIME := 0.25   # switch starts: the black screen fades in
const SINK_TIME := 0.9       # while the screen is black, we move to the other floor
const FADE_OUT_TIME := 0.5   # we arrived: the black screen fades away
const SONAR_COOLDOWN := 6.0  # the Q key has a cooldown: it calls the monster

# ---- god view ----
const GOD_VIEW_HEIGHT := 45.0               # how high the camera flies up
const CAM_REST := Vector3(0, 2.6708074, 0)  # normal camera position on the body

# @onready = wait until the scene is ready, then find these nodes
@onready var camera: Camera3D = $Camera3D
@onready var world_env: WorldEnvironment = $"../WorldEnvironment"
@onready var _monster: Node3D = $"../Monster"
@onready var _ping_sound: AudioStreamPlayer = $PingSound
@onready var _fade: ColorRect = $"../HUD/FadeRect"   # the black screen for the floor switch

var no_switch_count := 0    # how many "no switch zones" I stand in
var can_act := true         # game.gd turns this off when the game ends
var _transitioning := false # true while the floor switch animation plays
var _sonar_timer := 0.0     # cooldown timer for the Q key
var _god_view := false      # is the god view on?


# When the game starts: lock the mouse, and remember all the no-switch zones.
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# find every no-switch zone and make it tell us when the player walks in or out
	for zone in get_tree().get_nodes_in_group("no_switch_zone"):
		zone.body_entered.connect(_on_zone_entered)
		zone.body_exited.connect(_on_zone_exited)


# the player walked INTO a no-switch zone
func _on_zone_entered(body: Node3D) -> void:
	if body == self:
		no_switch_count += 1

# the player walked OUT of a no-switch zone
func _on_zone_exited(body: Node3D) -> void:
	if body == self:
		no_switch_count -= 1


# Here we handle the mouse and some keys.
func _unhandled_input(event: InputEvent) -> void:
	# move the mouse = turn the view. Left and right turns the body,
	# up and down only turns the camera, and it cannot flip over.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _god_view:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotation.x = clampf(
			camera.rotation.x - event.relative.y * MOUSE_SENSITIVITY,
			-PI / 2.0, PI / 2.0
		)
	elif event.is_action_pressed("ui_cancel"):
		# Esc: free the mouse so we can click other windows
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		# click the window: lock the mouse again
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# ---- press V: god view. The camera flies high above the player. ----
	elif event.is_action_pressed("god_view") and can_act and not _transitioning:
		_god_view = not _god_view
		if _god_view:
			camera.set_as_top_level(true)   # the camera leaves the body
			camera.global_position = global_position + Vector3(0, GOD_VIEW_HEIGHT, 0.01)
			camera.rotation = Vector3(-PI / 2, 0, 0)   # look straight down
		else:
			camera.set_as_top_level(false)
			camera.position = CAM_REST
			camera.rotation = Vector3.ZERO
	# ---- press Q: listen. The nearest shard answers with an echo.
	# But the sound also calls the monster. ----
	elif event.is_action_pressed("listen") and can_act and _sonar_timer <= 0.0 and not _transitioning:
		_sonar_timer = SONAR_COOLDOWN
		_ping_sound.play()
		_monster.hear_ping(global_position)   # the sound shows the monster where you are
		# only the nearest shard answers. The echo comes later if it is far away.
		var nearest: Node3D = null
		var nearest_d := INF
		for shard in get_tree().get_nodes_in_group("soul"):
			var d: float = shard.global_position.distance_to(global_position)
			if d < nearest_d:
				nearest_d = d
				nearest = shard
		if nearest != null:
			nearest.play_echo(nearest_d * 0.03)


# This runs many times every second. All movement code lives here.
func _physics_process(delta: float) -> void:
	_sonar_timer = maxf(_sonar_timer - delta, 0.0)

	# the god view camera always stays above the player
	if _god_view:
		camera.global_position = global_position + Vector3(0, GOD_VIEW_HEIGHT, 0.01)

	# ---------- press F: switch between the two floors ----------
	# While switching, this is the most important input. All other keys are ignored.
	if Input.is_action_just_pressed("switch_mind"):
		if _transitioning or not can_act:
			pass   # we are already switching, or the game is over: do nothing
		elif no_switch_count > 0:
			pass   # this is a no-switch zone: do nothing (so we never get stuck in a wall)
		else:
			_start_switch()

	# ---------- gravity ----------
	# if we are in the air, we fall faster and faster
	if not is_on_floor():
		velocity += get_gravity() * delta

	# ---------- jump ----------
	# only when we stand on the floor
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# ---------- move ----------
	# read the keys (WASD / arrows) and walk in that direction
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		# no keys pressed: slow down smoothly
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	# this line really moves the body and handles the walls
	move_and_slide()


# ---------- the floor switch: black screen first, then move in the dark ----------
# (the screen goes black so you cannot see the body pass through the floor)
func _start_switch() -> void:
	_transitioning = true
	set_physics_process(false)   # stop gravity and movement for a moment
	collision_mask = 0           # become a ghost, so the floor does not block us
	# where do we go? above the line = go down, below the line = go up
	var target_y := LOWER_FLOOR_Y if global_position.y > FLOOR_THRESHOLD else UPPER_FLOOR_Y
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, FADE_IN_TIME)    # screen goes black
	tw.tween_property(self, "global_position:y", target_y, SINK_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)  # move in the dark
	tw.tween_property(_fade, "modulate:a", 0.0, FADE_OUT_TIME)   # screen comes back
	tw.tween_callback(_finish_switch)


# the switch is done: give back the collisions and the physics
func _finish_switch() -> void:
	velocity = Vector3.ZERO
	collision_mask = 1
	_transitioning = false
	if can_act:
		set_physics_process(true)
	_apply_floor_look(global_position.y < FLOOR_THRESHOLD)


# ---------- the light of the two floors ----------
# lower floor: almost no light. upper floor: use the sky as the light.
func _apply_floor_look(in_deep: bool) -> void:
	var env := world_env.environment
	if in_deep:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = DEEP_AMBIENT
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_BG

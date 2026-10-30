extends Node3D
# This is the monster brain. It controls two bodies at the same time:
#   Upper - the body on the upper floor. You CAN see this one.
#   Deep  - the body on the lower floor. This one is INVISIBLE.
# Both bodies always stay at the same place (same x and z).
#
# How its eyes work: a red line moves left and right (the red light cone
# is only the picture of it). If the red line touches you, it chases you.
# Hide outside the red light for 3 seconds, and it loses you.
# On the lower floor you cannot see it - you can only hear its breathing.
#
# If you do not meet it for a long time, or it eats a shard,
# it teleports to the farthest place from you and starts hunting again.

signal caught   # "I caught the player" - game.gd hears this and shows the lose screen


# ================== settings (you can change these) ==================
const WALK_SPEED := 3.0        # walk speed when just patrolling (player is 5.0)
const CHASE_SPEED := 4.2       # speed when chasing the player
const SIGHT := 12.0            # how far the red line can see (meters)
const CONE_HALF := 0.9         # how far left and right the red line moves (radians)
const LINE_TOLERANCE := 0.14   # how "thick" the red line is (about 8 degrees)
const SWEEP_SPEED := 1.6       # how fast the red line sweeps left and right
const LOSE_SIGHT_TIME := 3.0   # stay out of the red light this long = it loses you
const SEARCH_TIME := 5.0       # how long it looks for you at your last place
const CATCH_DISTANCE := 1.3    # this close, on the same floor = caught
const TURN_SPEED := 6.0        # how fast the body turns
const FOLLOW_STRENGTH := 8.0   # how tight the "rope" pulls the lower body
const MAX_FOLLOW_SPEED := 8.0  # the biggest speed of that rope
const RELOCATE_AFTER := 25.0   # no contact for this long = teleport far away

enum State { PATROL, CHASE, SEARCH }

@onready var upper: CharacterBody3D = $Upper
@onready var deep: CharacterBody3D = $Deep
@onready var vision: Node3D = $Upper/VisionHolder   # the red cone and the red line

var state := State.PATROL
var _dir := Vector3.RIGHT      # the walking direction now
var _walk_timer := 0.0         # how long to keep walking this way
var _facing := 0.0             # which way the body looks (radians)
var _unseen_time := 0.0        # how many seconds the player was not seen
var _search_timer := 0.0       # time left in the search state
var _last_seen := Vector3.ZERO # the last place where I saw or heard the player
var _has_caught := false       # catch only happens once
var _contact_timer := 0.0      # counts seconds when the player is far away
var _open_cells: Array = []    # floor cells that are free on BOTH floors (for teleporting)
var _player: Node3D
var _hums: Array = []          # the breathing sound players on both bodies


func _ready() -> void:
	_pick_new_direction()
	_hums = [$Upper/Hum, $Deep/Hum]
	for hum in _hums:
		hum.finished.connect(hum.play)   # when the sound ends, play it again = a loop
		hum.play()                       # start the breathing sound


func _physics_process(delta: float) -> void:
	if _has_caught:
		return
	if _player == null:
		# first physics frame: find the player and remember all free floor cells
		_player = get_tree().get_first_node_in_group("player")
		_scan_open_cells()
		return

	# ---------- see: does the red line touch the player? ----------
	var seen := _can_see_player()
	if seen:
		_unseen_time = 0.0
		_last_seen = _player.global_position
		if state != State.CHASE:
			state = State.CHASE
	else:
		_unseen_time += delta

	# ---------- the three states ----------
	if state == State.PATROL:
		_patrol(delta)
	elif state == State.CHASE:
		_chase(delta)
		if _unseen_time >= LOSE_SIGHT_TIME:
			state = State.SEARCH
			_search_timer = SEARCH_TIME
	elif state == State.SEARCH:
		_search(delta)

	_update_visuals(delta)
	_check_catch()
	_check_idle_relocate(delta)


# ---------- patrol: walk straight. Hit a wall? Pick a new direction. ----------
func _patrol(delta: float) -> void:
	_walk_timer -= delta
	if _walk_timer <= 0:
		_pick_new_direction()
	upper.velocity.x = _dir.x * WALK_SPEED
	upper.velocity.z = _dir.z * WALK_SPEED
	upper.move_and_slide()
	# we want to walk but we do not move = we press a wall, pick a new direction
	if upper.get_real_velocity().length() < 0.5:
		_pick_new_direction()
	_follow()


# ---------- chase: run to the last place where I saw or heard the player ----------
func _chase(_delta: float) -> void:
	_move_upper_to(_last_seen, CHASE_SPEED)
	_follow()


# ---------- search: go to the last place, look around, then patrol again ----------
func _search(delta: float) -> void:
	if _flat_dist(upper.global_position, _last_seen) < 1.0:
		_give_up()
		return
	_search_timer -= delta
	if _search_timer <= 0:
		_give_up()
		return
	_move_upper_to(_last_seen, WALK_SPEED)
	_follow()


func _give_up() -> void:
	state = State.PATROL
	_pick_new_direction()


# move the upper body toward one point with a given speed
func _move_upper_to(target: Vector3, speed: float) -> void:
	var to: Vector3 = target - upper.global_position
	to.y = 0
	var dir := to.normalized() if to.length() > 0.05 else _dir
	upper.velocity.x = dir.x * speed
	upper.velocity.z = dir.z * speed
	upper.move_and_slide()


# ---------- the lower body: pulled by a "rope" toward the upper body ----------
# (we do not teleport, because the walls are not the same on both floors)
func _follow() -> void:
	var pull: Vector3 = upper.global_position - deep.global_position
	pull.y = 0
	if pull.length() > 0.01:
		var follow_speed := minf(pull.length() * FOLLOW_STRENGTH, MAX_FOLLOW_SPEED)
		deep.velocity = pull.normalized() * follow_speed
	else:
		deep.velocity = Vector3.ZERO
	deep.move_and_slide()


# ---------- can I see the player? Range + same floor + the red line on them ----------
func _can_see_player() -> bool:
	var to_p: Vector3 = _player.global_position - upper.global_position
	if absf(to_p.y) > 2.5:                      # different floor = cannot see
		return false
	if Vector2(to_p.x, to_p.z).length() > SIGHT:   # too far away
		return false
	# where is the red line pointing right now?
	var sweep := _facing + sin(Time.get_ticks_msec() / 1000.0 * SWEEP_SPEED) * CONE_HALF
	var player_yaw := atan2(-to_p.x, -to_p.z)
	return absf(wrapf(player_yaw - sweep, -PI, PI)) <= LINE_TOLERANCE


# ---------- turn the body slowly, and swing the red light and red line ----------
func _update_visuals(delta: float) -> void:
	var v := Vector3(upper.velocity.x, 0, upper.velocity.z)
	if v.length() > 0.3:
		var target_yaw := atan2(-v.x, -v.z)
		_facing = lerp_angle(_facing, target_yaw, minf(TURN_SPEED * delta, 1.0))
	vision.rotation.y = _facing + sin(Time.get_ticks_msec() / 1000.0 * SWEEP_SPEED) * CONE_HALF


# ---------- catch check (both bodies can catch, but same floor only) ----------
func _check_catch() -> void:
	for body: CharacterBody3D in [upper, deep]:
		var to_target: Vector3 = _player.global_position - body.global_position
		if absf(to_target.y) < 2.5 and Vector2(to_target.x, to_target.z).length() < CATCH_DISTANCE:
			_has_caught = true
			caught.emit()
			return


# ---------- the player pressed Q (listen): the sound shows me where they are ----------
func hear_ping(pos: Vector3) -> void:
	_last_seen = pos
	_unseen_time = 0.0
	state = State.CHASE


# ---------- teleport both bodies to the free cell farthest from the player ----------
func relocate() -> void:
	if _open_cells.is_empty() or _player == null:
		return
	var best: Vector3 = _open_cells[0]
	var best_d := -1.0
	for cell: Vector3 in _open_cells:
		var d := _flat_dist(cell, _player.global_position)
		if d > best_d:
			best_d = d
			best = cell
	upper.global_position = Vector3(best.x, 5.0, best.z)
	deep.global_position = Vector3(best.x, 0.0, best.z)
	upper.velocity = Vector3.ZERO
	deep.velocity = Vector3.ZERO
	state = State.PATROL
	_unseen_time = 0.0
	_pick_new_direction()


# ---------- player far away for too long = teleport and hunt again ----------
func _check_idle_relocate(delta: float) -> void:
	if _flat_dist(upper.global_position, _player.global_position) < 15.0:
		_contact_timer = 0.0
		return
	_contact_timer += delta
	if _contact_timer >= RELOCATE_AFTER:
		_contact_timer = 0.0
		relocate()


# ================== small helpers ==================

# pick one of the four straight directions (walking diagonal gets stuck on corners)
func _pick_new_direction() -> void:
	_walk_timer = randf_range(2.0, 5.0)
	var dirs: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]
	_dir = dirs.pick_random()


# the distance between two points, ignoring the height (only x and z)
func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# at the start, check every floor cell. A cell is "free" only when
# there is no wall on the lower floor AND no wall on the upper floor.
func _scan_open_cells() -> void:
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	for r in 15:
		for c in 15:
			var pos := Vector3((c - 7) * 4.0, 0, (r - 7) * 4.0)
			if _cell_clear(space, sphere, pos + Vector3(0, 1.0, 0)) \
					and _cell_clear(space, sphere, pos + Vector3(0, 6.0, 0)):
				_open_cells.append(pos)


# true when nothing solid is inside this small sphere
func _cell_clear(space: PhysicsDirectSpaceState3D, sphere: SphereShape3D, center: Vector3) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), center)
	params.collision_mask = 1
	params.exclude = [upper.get_rid(), deep.get_rid()]   # do not count my own bodies
	return space.intersect_shape(params, 1).is_empty()

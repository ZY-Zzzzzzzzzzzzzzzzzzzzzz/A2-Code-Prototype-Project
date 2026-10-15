extends Node3D
# 心魔（完整设计版）。
# 上层身体 Upper：看得见——深红胶囊 + 一束左右扫动的红光锥 + 一条红色"视线线"
# 下层身体 Deep ：完全隐形，但它一直在：会追你、会抓你、会吞碎片。
#   在下层你只能靠"声音"判断它的远近——靠近时能听到低沉的呼吸声。
#
# 视线机制：那条红线绕着它的朝向左右来回扫（红光锥只是红线的可视化范围）。
# 红线扫到你 = 被发现 → 追击；脱离红光区域连续 3 秒 = 甩掉它，
# 它会先去你最后出现的位置找一圈，找不到才恢复巡逻。
#
# 反挂机机制：如果太久（25 秒）没"接触"过它，或者它吞掉了一块碎片，
# 它会把两只身体一起传送到离玩家最远的通路格，重新开始寻找玩家。

signal caught


# ================== 手感参数（随便调） ==================
const WALK_SPEED := 3.0        # 巡逻速度（玩家 5.0）
const CHASE_SPEED := 4.2       # 追击速度
const SIGHT := 12.0            # 视线红线长度（米）＝红光锥长度
const CONE_HALF := 0.9         # 红线摆动半角（弧度，约 51°）＝红光锥半角
const LINE_TOLERANCE := 0.14   # 红线的"粗细"（弧度，约 8°）：扫到就算看见
const SWEEP_SPEED := 1.6       # 红线左右扫的速度（弧度/秒）
const LOSE_SIGHT_TIME := 3.0   # 脱离视线多久才甩掉它（秒）
const SEARCH_TIME := 5.0       # 在最后出现位置找多久（秒）
const CATCH_DISTANCE := 1.3    # 同层贴这么近 = 抓住
const TURN_SPEED := 6.0        # 转身快慢
const FOLLOW_STRENGTH := 8.0   # 下层身体的"绳子"松紧
const MAX_FOLLOW_SPEED := 8.0  # 绳子最大拽速
const RELOCATE_AFTER := 25.0   # 玩家多久没接触过它就传送（秒）

enum State { PATROL, CHASE, SEARCH }

@onready var upper: CharacterBody3D = $Upper
@onready var deep: CharacterBody3D = $Deep
@onready var vision: Node3D = $Upper/VisionHolder   # 红光锥+红线，随视线转动

var state := State.PATROL
var _dir := Vector3.RIGHT      # 当前巡逻方向
var _walk_timer := 0.0         # 沿该方向还要走多久
var _facing := 0.0             # 朝向（弧度，绕 Y 轴）
var _unseen_time := 0.0        # 连续多久没看见玩家
var _search_timer := 0.0       # 搜索状态剩余时间
var _last_seen := Vector3.ZERO # 最后看见玩家（或听到声音）的位置
var _has_caught := false
var _contact_timer := 0.0      # 玩家离它 15 米内会清零；攒满就传送
var _open_cells: Array = []    # 上下两层都通的格子（世界坐标），传送用
var _player: Node3D
var _hums: Array = []          # 两只身体上的呼吸声播放器


func _ready() -> void:
	_pick_new_direction()
	_hums = [$Upper/Hum, $Deep/Hum]
	for hum in _hums:
		hum.finished.connect(hum.play)   # 播完立刻再播 = 循环呼吸声
		hum.play()                       # 别忘了让它第一次响起来（之前漏了这行，呼吸声一直没响过）


func _physics_process(delta: float) -> void:
	if _has_caught:
		return
	if _player == null:
		# 第一物理帧：玩家和物理世界都就绪了，把"上下都通"的格子全部记下来
		_player = get_tree().get_first_node_in_group("player")
		_scan_open_cells()
		return

	# ---------- 感知：红线扫到玩家了吗 ----------
	var seen := _can_see_player()
	if seen:
		_unseen_time = 0.0
		_last_seen = _player.global_position
		if state != State.CHASE:
			state = State.CHASE
	else:
		_unseen_time += delta

	# ---------- 状态机 ----------
	if state == State.PATROL:
		_patrol(delta)
	elif state == State.CHASE:
		_chase(delta)
		if _unseen_time >= LOSE_SIGHT_TIME:   # 甩掉它的唯一方法：躲出红光 3 秒
			state = State.SEARCH
			_search_timer = SEARCH_TIME
	elif state == State.SEARCH:
		_search(delta)

	_update_visuals(delta)
	_check_catch()
	_check_idle_relocate(delta)


# ---------- 巡逻：直走，撞墙换向，定期自己也换个方向 ----------
func _patrol(delta: float) -> void:
	_walk_timer -= delta
	if _walk_timer <= 0:
		_pick_new_direction()
	upper.velocity.x = _dir.x * WALK_SPEED
	upper.velocity.z = _dir.z * WALK_SPEED
	upper.move_and_slide()
	if upper.get_real_velocity().length() < 0.5:   # 想走却没挪动 = 顶墙了
		_pick_new_direction()
	_follow()


# ---------- 追击：奔向最后知道的位置（看见时一直刷新成玩家脚下） ----------
func _chase(_delta: float) -> void:
	_move_upper_to(_last_seen, CHASE_SPEED)
	_follow()


# ---------- 搜索：去最后出现的位置找一圈，找不到就恢复巡逻 ----------
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


func _move_upper_to(target: Vector3, speed: float) -> void:
	var to: Vector3 = target - upper.global_position
	to.y = 0
	var dir := to.normalized() if to.length() > 0.05 else _dir
	upper.velocity.x = dir.x * speed
	upper.velocity.z = dir.z * speed
	upper.move_and_slide()


# ---------- 下层身体：被"绳子"拴着追上层（不传送，防穿模） ----------
func _follow() -> void:
	var pull: Vector3 = upper.global_position - deep.global_position
	pull.y = 0
	if pull.length() > 0.01:
		var follow_speed := minf(pull.length() * FOLLOW_STRENGTH, MAX_FOLLOW_SPEED)
		deep.velocity = pull.normalized() * follow_speed
	else:
		deep.velocity = Vector3.ZERO
	deep.move_and_slide()


# ---------- 视线判定：范围 + 同层 + 扫动的红线是否压到玩家 ----------
func _can_see_player() -> bool:
	var to_p: Vector3 = _player.global_position - upper.global_position
	if absf(to_p.y) > 2.5:                      # 不同层看不见
		return false
	if Vector2(to_p.x, to_p.z).length() > SIGHT:
		return false
	var sweep := _facing + sin(Time.get_ticks_msec() / 1000.0 * SWEEP_SPEED) * CONE_HALF
	var player_yaw := atan2(-to_p.x, -to_p.z)
	return absf(wrapf(player_yaw - sweep, -PI, PI)) <= LINE_TOLERANCE


# ---------- 姿态：身体缓慢转向移动方向，红光锥+红线一起扫 ----------
func _update_visuals(delta: float) -> void:
	var v := Vector3(upper.velocity.x, 0, upper.velocity.z)
	if v.length() > 0.3:
		var target_yaw := atan2(-v.x, -v.z)
		_facing = lerp_angle(_facing, target_yaw, minf(TURN_SPEED * delta, 1.0))
	vision.rotation.y = _facing + sin(Time.get_ticks_msec() / 1000.0 * SWEEP_SPEED) * CONE_HALF


# ---------- 抓住判定（两只身体都算，必须和玩家同层） ----------
func _check_catch() -> void:
	for body: CharacterBody3D in [upper, deep]:
		var to_target: Vector3 = _player.global_position - body.global_position
		if absf(to_target.y) < 2.5 and Vector2(to_target.x, to_target.z).length() < CATCH_DISTANCE:
			_has_caught = true
			caught.emit()
			return


# ---------- 玩家按了"聆听"（Q）：声音暴露位置，立刻追过去 ----------
func hear_ping(pos: Vector3) -> void:
	_last_seen = pos
	_unseen_time = 0.0
	state = State.CHASE


# ---------- 传送到离玩家最远的通路格（两只一起挪） ----------
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


# ---------- 玩家 15 米外攒满 25 秒 = "好久没看到怪" → 自动传送 ----------
func _check_idle_relocate(delta: float) -> void:
	if _flat_dist(upper.global_position, _player.global_position) < 15.0:
		_contact_timer = 0.0
		return
	_contact_timer += delta
	if _contact_timer >= RELOCATE_AFTER:
		_contact_timer = 0.0
		relocate()


# ================== 工具函数 ==================

func _pick_new_direction() -> void:
	_walk_timer = randf_range(2.0, 5.0)
	var dirs: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]
	_dir = dirs.pick_random()


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# 开局逐格探测：上下两层都没有墙的格子才配叫"通路"（传送落点从这里挑）
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


func _cell_clear(space: PhysicsDirectSpaceState3D, sphere: SphereShape3D, center: Vector3) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), center)
	params.collision_mask = 1
	params.exclude = [upper.get_rid(), deep.get_rid()]   # 别把自己算成墙
	return space.intersect_shape(params, 1).is_empty()

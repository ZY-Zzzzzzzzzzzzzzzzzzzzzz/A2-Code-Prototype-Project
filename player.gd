extends CharacterBody3D
# 玩家：移动 / 鼠标视角 / 跳跃 / F 意识切换（黑场+缓降）/ Q 聆听 / V 上帝视角


# ================== 可以随便调的参数 ==================
const SPEED = 5.0                  # 走路速度（米/秒）
const JUMP_VELOCITY = 4.5          # 起跳向上的速度
const MOUSE_SENSITIVITY = 0.0025   # 鼠标灵敏度

# ---- 两层意识的高度 ----
const UPPER_FLOOR_Y = 4.0    # 站在上层时玩家原点的 y
const LOWER_FLOOR_Y = -1.0   # 站在下层时玩家原点的 y
const FLOOR_THRESHOLD = 2.0  # 判断在哪层的分界线

# 下层"潜意识"的环境光：接近纯黑（0~1 之间调）
const DEEP_AMBIENT := Color(0.015, 0.015, 0.02)

const FADE_IN_TIME := 0.25    # 穿梭开始：黑场淡入
const SINK_TIME := 0.9        # 黑场遮住屏幕期间：实际完成升降
const FADE_OUT_TIME := 0.5    # 到达后：黑场淡出
const SONAR_COOLDOWN := 6.0   # 聆听（Q）的冷却：招怪是有代价的

# ---- 上帝视角 ----
const GOD_VIEW_HEIGHT := 45.0                    # 飞到玩家头顶多高
const CAM_REST := Vector3(0, 2.6708074, 0)       # 正常视角下相机在身上挂的位置

@onready var camera: Camera3D = $Camera3D
@onready var world_env: WorldEnvironment = $"../WorldEnvironment"
@onready var _monster: Node3D = $"../Monster"
@onready var _ping_sound: AudioStreamPlayer = $PingSound
@onready var _fade: ColorRect = $"../HUD/FadeRect"   # 穿梭时遮住整块屏幕的黑片

var no_switch_count := 0    # 站在几个禁切区里
var can_act := true         # 游戏结束时被 game.gd 关掉：F / Q / V 全部失效
var _transitioning := false # 正在穿梭（期间升降指令最高优先级：吞掉一切输入）
var _sonar_timer := 0.0
var _god_view := false      # 上帝视角开关


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# 收集场景里所有禁切区，让它们在玩家进/出时喊一声，我们负责计数
	for zone in get_tree().get_nodes_in_group("no_switch_zone"):
		zone.body_entered.connect(_on_zone_entered)
		zone.body_exited.connect(_on_zone_exited)


func _on_zone_entered(body: Node3D) -> void:
	if body == self:
		no_switch_count += 1

func _on_zone_exited(body: Node3D) -> void:
	if body == self:
		no_switch_count -= 1


func _unhandled_input(event: InputEvent) -> void:
	# ---- 鼠标视角（上帝视角时不响应，不然身体会在脚下乱转）----
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _god_view:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotation.x = clampf(
			camera.rotation.x - event.relative.y * MOUSE_SENSITIVITY,
			-PI / 2.0, PI / 2.0
		)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# ---- V 上帝视角：切到头顶俯拍，再按一次回到第一人称 ----
	elif event.is_action_pressed("god_view") and can_act and not _transitioning:
		_god_view = not _god_view
		if _god_view:
			camera.set_as_top_level(true)   # 脱离玩家，挂到世界上
			camera.global_position = global_position + Vector3(0, GOD_VIEW_HEIGHT, 0.01)
			camera.rotation = Vector3(-PI / 2, 0, 0)   # 竖直朝下看
		else:
			camera.set_as_top_level(false)
			camera.position = CAM_REST
			camera.rotation = Vector3.ZERO
	# ---- Q 聆听（声呐）：代价是把那个东西引过来 ----
	elif event.is_action_pressed("listen") and can_act and _sonar_timer <= 0.0 and not _transitioning:
		_sonar_timer = SONAR_COOLDOWN
		_ping_sound.play()
		_monster.hear_ping(global_position)   # 代价：声音暴露位置
		# 只让离你最近的一颗碎片回声（全部一起响只会糊成一团）：
		# ping 之后它延迟一下才回，回得越慢说明越远，像真的声呐
		var nearest: Node3D = null
		var nearest_d := INF
		for shard in get_tree().get_nodes_in_group("soul"):
			var d: float = shard.global_position.distance_to(global_position)
			if d < nearest_d:
				nearest_d = d
				nearest = shard
		if nearest != null:
			nearest.play_echo(nearest_d * 0.03)


func _physics_process(delta: float) -> void:
	_sonar_timer = maxf(_sonar_timer - delta, 0.0)

	# 上帝视角：相机始终悬在玩家头顶正上方（跟着人走）
	if _god_view:
		camera.global_position = global_position + Vector3(0, GOD_VIEW_HEIGHT, 0.01)

	# ---------- 意识切换（F 键）：穿梭期间指令最高优先级，其余输入一律吞掉 ----------
	if Input.is_action_just_pressed("switch_mind"):
		if _transitioning or not can_act:
			pass   # 正在穿梭 / 游戏已结束：不理会
		elif no_switch_count > 0:
			pass   # 禁切区：防穿模
		else:
			_start_switch()

	# ---------- 重力 ----------
	if not is_on_floor():
		velocity += get_gravity() * delta

	# ---------- 跳跃 ----------
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# ---------- 移动 ----------
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()


# ---------- 意识穿梭：黑场遮住镜头 → 黑暗中缓缓升降 → 淡出 ----------
# 之前直接沉下去会看见身体穿过楼板（穿模），所以用一块黑色 UI 盖住整块屏幕
func _start_switch() -> void:
	_transitioning = true
	set_physics_process(false)   # 动画期间暂停物理：不受重力、不能移动
	collision_mask = 0           # 穿梭时变成"幽灵"，不然会被楼板卡住
	var target_y := LOWER_FLOOR_Y if global_position.y > FLOOR_THRESHOLD else UPPER_FLOOR_Y
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, FADE_IN_TIME)    # 淡入黑场
	tw.tween_property(self, "global_position:y", target_y, SINK_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)  # 遮住时完成升降
	tw.tween_property(_fade, "modulate:a", 0.0, FADE_OUT_TIME)   # 淡出
	tw.tween_callback(_finish_switch)


func _finish_switch() -> void:
	velocity = Vector3.ZERO
	collision_mask = 1
	_transitioning = false
	if can_act:
		set_physics_process(true)
	_apply_floor_look(global_position.y < FLOOR_THRESHOLD)


# ---------- 两层的环境光切换 ----------
func _apply_floor_look(in_deep: bool) -> void:
	var env := world_env.environment
	if in_deep:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = DEEP_AMBIENT
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_BG

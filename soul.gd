extends Area3D
# 记忆碎片：只存在于潜意识（下层）、黑暗中自己发光的小球。
# 玩家碰到 → collected（计入得分）；心魔碰到 → eaten（碎片被永久吞噬！）
# 它还随身带一个"回声"音效：玩家按 Q 聆听时，碎片按距离延迟回一声，
# 像声呐一样——这就是在漆黑下层找碎片的办法。


# ================== 手感参数（随便调） ==================
const SPIN_SPEED := 2.0     # 自转速度（弧度/秒）
const FLOAT_SPEED := 2.0    # 上下浮动快慢
const FLOAT_RANGE := 0.3    # 上下浮动幅度（米）
const HOVER_HEIGHT := 0.9   # 悬浮中心离地高度

signal collected   # "被玩家捡了"——game.gd 计分
signal eaten       # "被心魔吞了"——game.gd 缩减总数并让心魔传送

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var _echo: AudioStreamPlayer3D = $Echo

var _time := 0.0   # 自己的秒表，驱动浮动


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_time = randf() * TAU   # 随机起点，十颗碎片起伏参差不齐


func _process(delta: float) -> void:
	_time += delta
	rotate_y(SPIN_SPEED * delta)
	mesh.position.y = HOVER_HEIGHT + sin(_time * FLOAT_SPEED) * FLOAT_RANGE


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_collected()
	elif body.is_in_group("monster"):
		_eaten()


# 玩家按 Q 时被调用：delay = 声音从玩家传过来的时间（距离越远越晚响）
func play_echo(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_inside_tree():   # 等待期间碎片可能已经被捡走删掉了
		_echo.play()


func _collected() -> void:
	collected.emit()
	_disappear(0.2)


func _eaten() -> void:
	eaten.emit()
	_disappear(0.35)   # 被吞掉时消失得慢一点，像在挣扎


func _disappear(duration: float) -> void:
	# 关掉感应防止重复触发；正在物理回调里不许当场改，所以 set_deferred
	set_deferred("monitoring", false)
	var tween := create_tween()
	tween.tween_property(mesh, "scale", Vector3.ONE * 0.01, duration)
	tween.tween_callback(queue_free)

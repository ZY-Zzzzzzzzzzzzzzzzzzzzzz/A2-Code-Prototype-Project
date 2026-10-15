extends Node3D
# 这个脚本挂在场景根节点 Game 上，是整个游戏的"裁判"。
# 职责：数碎片、更新 HUD、播内心独白、判断胜利和失败、管理重开。
# （移动是 player.gd 的事，碎片是 soul.gd 的事，那个东西是 monster.gd 的事）


# ================== 可以调的参数 ==================
# 和 player.gd 里的 FLOOR_THRESHOLD 保持一致（高于它=上层表意识）
const FLOOR_THRESHOLD := 2.0

# 两个"层"的名字（中英双语）
const FLOOR_NAME_TOP := "表意识 · Waking Mind"
const FLOOR_NAME_BOTTOM := "潜意识 · Subconscious"

# 捡到碎片时的内心独白（每条 [中文, English]，上下两行）。
# 开局洗牌、按抽取顺序播放、不重复；一轮用完重新洗
const QUOTES := [
	["我刚才要去哪儿来着？",
	 "What was I looking for, again?"],
	["这里有人吗？……算了。",
	 "Is anyone here? ...Never mind."],
	["我是不是来过这里？",
	 "Have I been here before?"],
	["先找个出口吧。",
	 "Let me find a way out first."],
	["明明看着挺近的。",
	 "It looked so close just now."],
	["又是这儿。我怎么又绕回来了？",
	 "Here again? How did I end up back here?"],
	["墙而已。……我摸一下。",
	 "Just a wall. ...Let me touch it."],
	["刚才那个角落，有东西吗？",
	 "Was there something in that corner just now?"],
	["有人在说话？",
	 "Is someone talking?"],
	["……是在叫我吗？",
	 "...Are they calling me?"],
	["……让我待一会儿。",
	 "...Let me stay here a little while."],
	["你还在吗？",
	 "Are you still there?"],
	["是这边吗？应该是这边。",
	 "This way? It should be this way."],
	["这里怎会是一面墙。",
	 "Since when was there a wall here?"],
]

# 碎片被吞掉时的提示（它吃了就没了，总数会变少）
const QUOTE_EATEN := ["有一块碎片……被黑暗里的什么东西吞掉了。",
	"Something in the dark devoured a shard."]

# 结算文案：不说教、不点名，只有"我"的感受
const TEXT_WIN := "……好刺眼的光。

…Such a blinding light.

按任意键，重新经历一遍 · Press any key"
const TEXT_LOSE := "好困，好困……
或许我应该好好休息一下了。

So sleepy… maybe I should just rest for a while.

按任意键，再试一次 · Press any key to try again"

@onready var player: CharacterBody3D = $Player
@onready var monster: Node3D = $Monster
@onready var score_label: Label = $HUD/ScoreLabel
@onready var floor_label: Label = $HUD/FloorLabel
@onready var quote_label: Label = $HUD/QuoteLabel
@onready var result_label: Label = $HUD/ResultLabel

var score := 0        # 已捡到
var total := 0        # 剩下需要捡的总数（碎片被吞会变少）
var is_over := false  # 游戏结束了吗

var _quote_tween: Tween
var _quote_deck: Array = []   # 洗过的台词牌堆，抽一张少一张


func _ready() -> void:
	result_label.visible = false
	_quote_deck = QUOTES.duplicate()
	_quote_deck.shuffle()
	var shards := get_tree().get_nodes_in_group("soul")
	total = shards.size()
	score_label.text = "记忆碎片 0 / %d · Memory 0 / %d" % [total, total]
	for shard in shards:
		shard.collected.connect(_on_shard_collected)
		shard.eaten.connect(_on_shard_eaten)
	monster.caught.connect(_lose)


func _update_score_text() -> void:
	score_label.text = "记忆碎片 %d / %d · Memory %d / %d" % [score, total, score, total]


func _on_shard_collected() -> void:
	if is_over:
		return
	score += 1
	_update_score_text()
	# 从牌堆抽一句；抽空了就重新洗一副
	if _quote_deck.is_empty():
		_quote_deck = QUOTES.duplicate()
		_quote_deck.shuffle()
	_show_quote(_quote_deck.pop_back())
	if score >= total:
		_win()


# 心魔吞掉了一块碎片：它永久消失，通关所需总数也变少（保住剩下的！）
func _on_shard_eaten() -> void:
	if is_over:
		return
	total -= 1
	_update_score_text()
	_show_quote(QUOTE_EATEN)
	if score >= total:
		_win()
	monster.relocate()   # 吃饱了 → 传送到离你最远的角落重新找你


# 显示一句独白：立刻显形 → 停 3 秒 → 1 秒淡出
func _show_quote(pair: Array) -> void:
	quote_label.text = "%s\n%s" % [pair[0], pair[1]]
	quote_label.modulate.a = 1.0
	if _quote_tween:
		_quote_tween.kill()
	_quote_tween = create_tween()
	_quote_tween.tween_interval(3.0)
	_quote_tween.tween_property(quote_label, "modulate:a", 0.0, 1.0)


func _end_game(text: String) -> void:
	is_over = true
	player.can_act = false                 # F / Q / V 全部失效
	player.set_physics_process(false)      # 冻结玩家
	monster.set_physics_process(false)     # 那个东西也停下
	result_label.text = text
	result_label.visible = true


func _win() -> void:
	if is_over:
		return
	_end_game(TEXT_WIN)


func _lose() -> void:
	if is_over:
		return
	_end_game(TEXT_LOSE)


func _unhandled_input(event: InputEvent) -> void:
	if is_over and event is InputEventKey and event.pressed:
		get_tree().reload_current_scene()


func _process(_delta: float) -> void:
	if player.global_position.y > FLOOR_THRESHOLD:
		floor_label.text = FLOOR_NAME_TOP
	else:
		floor_label.text = FLOOR_NAME_BOTTOM

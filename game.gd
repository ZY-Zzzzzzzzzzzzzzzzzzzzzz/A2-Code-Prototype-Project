extends Node3D
# This is the game manager. It sits on the root node "Game".
# Its jobs: count the shards, show the HUD text, show the quotes,
# and decide when the player wins or loses.


# ================== settings (you can change these) ==================
# same as in player.gd: above this y = upper floor
const FLOOR_THRESHOLD := 2.0

# the names of the two floors (shown in the top left corner)
const FLOOR_NAME_TOP := "表意识 · Waking Mind"
const FLOOR_NAME_BOTTOM := "潜意识 · Subconscious"

# quotes: every shard shows one line when you pick it up.
# They come in a random order, and no line repeats until the deck is empty.
const QUOTES := [
	["What was I looking for, again?"],
	["Is anyone here? ...Never mind."],
	["Have I been here before?"],
	["Let me find a way out first."],
	["It looked so close just now."],
	["Here again? How did I end up back here?"],
	["Just a wall. ...Let me touch it."],
	["Was there something in that corner just now?"],
	["Is someone talking?"],
	["...Are they calling me?"],
	["...Let me stay here a little while."],
	["Are you still there?"],
	["This way? It should be this way."],
	["Since when was there a wall here?"],
]

# this text shows when the monster eats a shard. The shard is gone forever.
const QUOTE_EATEN := ["Something in the dark devoured a shard."]

# the end texts. Win: you wake up. Lose: you fall asleep.
const TEXT_WIN := "…Such a blinding light.

Press any key"

#The text is showed, when take win.
const TEXT_LOSE := "So sleepy… maybe I should just rest for a while.

Press any key to try again"

@onready var player: CharacterBody3D = $Player
@onready var monster: Node3D = $Monster
@onready var score_label: Label = $HUD/ScoreLabel
@onready var floor_label: Label = $HUD/FloorLabel
@onready var quote_label: Label = $HUD/QuoteLabel
@onready var result_label: Label = $HUD/ResultLabel

var score := 0        # shards picked up
var total := 0        # shards still needed (it gets smaller when one is eaten)
var is_over := false  # is the game finished? (win or lose)

var _quote_tween: Tween
var _quote_deck: Array = []   # the quote deck. Draw one card, it is gone.


func _ready() -> void:
	result_label.visible = false
	# shuffle the quotes and find all shards in the scene
	_quote_deck = QUOTES.duplicate()
	_quote_deck.shuffle()
	var shards := get_tree().get_nodes_in_group("soul")
	total = shards.size()
	score_label.text = "记忆碎片 0 / %d · Memory 0 / %d" % [total, total]
	# every shard tells me when it is collected or eaten
	for shard in shards:
		shard.collected.connect(_on_shard_collected)
		shard.eaten.connect(_on_shard_eaten)
	# the monster tells me when it catches the player
	monster.caught.connect(_lose)


func _update_score_text() -> void:
	score_label.text = "记忆碎片 %d / %d · Memory %d / %d" % [score, total, score, total]


# player picked up a shard: +1 score, show a quote. All shards = you win.
func _on_shard_collected() -> void:
	if is_over:
		return
	score += 1
	_update_score_text()
	# draw one quote from the deck. If the deck is empty, shuffle a new one.
	if _quote_deck.is_empty():
		_quote_deck = QUOTES.duplicate()
		_quote_deck.shuffle()
	_show_quote(_quote_deck.pop_back())
	if score >= total:
		_win()


# the monster ate a shard: the shard is gone, so the total goes down.
# Protect the shards!
func _on_shard_eaten() -> void:
	if is_over:
		return
	total -= 1
	_update_score_text()
	_show_quote(QUOTE_EATEN)
	if score >= total:
		_win()
	monster.relocate()   # it is full now -> teleport far away and hunt again


# show one quote: it appears, waits 3 seconds, then fades out in 1 second
func _show_quote(pair: Array) -> void:
	# join puts every line of the array together:
	# 1 line (English only) or 2 lines (Chinese + English) both work
	quote_label.text = "\n".join(pair)
	quote_label.modulate.a = 1.0
	if _quote_tween:
		_quote_tween.kill()   # the old quote was still fading? Stop it.
	_quote_tween = create_tween()
	_quote_tween.tween_interval(3.0)
	_quote_tween.tween_property(quote_label, "modulate:a", 0.0, 1.0)


# the game ends (win or lose): stop the player and the monster, show the text
func _end_game(text: String) -> void:
	is_over = true
	player.can_act = false                 # F / Q / V do not work anymore
	player.set_physics_process(false)      # freeze the player
	monster.set_physics_process(false)     # stop the monster too
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


# after the game ends: press any key to restart the whole scene
func _unhandled_input(event: InputEvent) -> void:
	if is_over and event is InputEventKey and event.pressed:
		get_tree().reload_current_scene()


# every frame: show which floor the player is on (very useful in the dark)
func _process(_delta: float) -> void:
	if player.global_position.y > FLOOR_THRESHOLD:
		floor_label.text = FLOOR_NAME_TOP
	else:
		floor_label.text = FLOOR_NAME_BOTTOM

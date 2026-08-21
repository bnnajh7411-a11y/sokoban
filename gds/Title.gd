extends Node2D

const ENTRY_TILE_ATLAS: Vector2i = Vector2i(2, 0)
const PLAYER_MOVE_SFX: AudioStream = preload("res://audios/u_2fbuaev0zn-select-sound-121244.mp3")
const BUTTON_PRESS_SFX: AudioStream = preload("res://audios/slodkabonanza-pop-sound-effect-197846.mp3")
const REVEAL_DURATION: float = 1.0
const START_IN_ACTIVE_STATE_META_KEY: StringName = &"title_start_in_active_state"
const STAGE_SCENE_PATHS: Array[String] = [
	"res://scenes/Stage1.tscn",
	"res://scenes/Stage2.tscn",
	"res://scenes/Stage3.tscn",
	"res://scenes/Stage4.tscn",
	"res://scenes/Stage5.tscn",
	"res://scenes/Stage6.tscn",
]

@onready var tile_map_layer: TileMapLayer = $TileMapLayer
@onready var player: GridActor = $Player
@onready var stage_number: Control = $CanvasLayer/StageNumber
@onready var title_overlay: Control = $CanvasLayer/ClearOverlay
@onready var start_button: Button = $CanvasLayer/ClearOverlay/CenterContainer/VBoxContainer/StartButton
@onready var exit_button: Button = $CanvasLayer/ClearOverlay/CenterContainer/VBoxContainer/ExitButton

var _is_starting: bool = false
var _is_entering_stage: bool = false
var _entry_cell_to_scene_path: Dictionary = {}
var _title_overlay_locked_hidden: bool = false


func _ready() -> void:
	if not start_button.pressed.is_connected(_on_start_button_pressed):
		start_button.pressed.connect(_on_start_button_pressed)
	if not exit_button.pressed.is_connected(_on_exit_button_pressed):
		exit_button.pressed.connect(_on_exit_button_pressed)
	if not player.move_started.is_connected(_on_player_move_started):
		player.move_started.connect(_on_player_move_started)
	if not player.move_finished.is_connected(_on_player_move_finished):
		player.move_finished.connect(_on_player_move_finished)

	_collect_stage_entry_cells()
	if _should_start_in_active_state():
		_lock_title_overlay_hidden()
		_set_reveal_state(1.0)
		if player != null:
			player.controllable = true
	else:
		_set_reveal_state(0.0)
		if player != null:
			player.controllable = false


func _on_start_button_pressed() -> void:
	if _is_starting:
		return

	_is_starting = true
	start_button.disabled = true
	exit_button.disabled = true
	_play_button_press_sfx()
	_lock_title_overlay_hidden()
	await _reveal_title_world()
	if player != null:
		player.controllable = true


func _on_exit_button_pressed() -> void:
	_play_button_press_sfx()
	await get_tree().create_timer(0.12).timeout
	get_tree().quit()


func _on_player_move_started(actor: Node, _from_cell: Vector2i, _to_cell: Vector2i, _direction: Vector2i) -> void:
	if actor != player:
		return

	_play_player_move_sfx()


func _on_player_move_finished(actor: Node, _from_cell: Vector2i, to_cell: Vector2i, _direction: Vector2i) -> void:
	if actor != player or _is_entering_stage:
		return

	_check_for_stage_entry(to_cell)


func _collect_stage_entry_cells() -> void:
	_entry_cell_to_scene_path.clear()
	if tile_map_layer == null:
		return

	var entry_cells: Array[Vector2i] = []
	for cell in tile_map_layer.get_used_cells():
		if tile_map_layer.get_cell_atlas_coords(cell) == ENTRY_TILE_ATLAS:
			entry_cells.append(cell)

	entry_cells.sort_custom(Callable(self, "_compare_cells"))

	var entry_count: int = min(entry_cells.size(), STAGE_SCENE_PATHS.size())
	for index in range(entry_count):
		_entry_cell_to_scene_path[entry_cells[index]] = STAGE_SCENE_PATHS[index]


func _compare_cells(a: Vector2i, b: Vector2i) -> bool:
	if a.y == b.y:
		return a.x < b.x
	return a.y < b.y


func _set_reveal_state(alpha: float) -> void:
	var clamped_alpha: float = clampf(alpha, 0.0, 1.0)

	if tile_map_layer != null:
		tile_map_layer.visible = clamped_alpha > 0.0
		tile_map_layer.modulate.a = clamped_alpha

	if player != null:
		player.visible = clamped_alpha > 0.0
		player.modulate.a = clamped_alpha

	if stage_number != null:
		stage_number.visible = clamped_alpha > 0.0
		stage_number.modulate.a = clamped_alpha

	if title_overlay != null:
		if _title_overlay_locked_hidden:
			title_overlay.hide()
			title_overlay.modulate.a = 0.0
		else:
			title_overlay.show()
			title_overlay.modulate.a = 1.0 - clamped_alpha


func _reveal_title_world() -> void:
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_set_reveal_state, 0.0, 1.0, REVEAL_DURATION)
	await tween.finished
	_lock_title_overlay_hidden()


func _check_for_stage_entry(cell: Vector2i) -> void:
	if _is_entering_stage:
		return

	if not _entry_cell_to_scene_path.has(cell):
		return

	var scene_path: String = String(_entry_cell_to_scene_path[cell])
	if scene_path.is_empty():
		return

	_is_entering_stage = true
	player.controllable = false
	var change_error: Error = get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		_is_entering_stage = false
		player.controllable = true
		push_error("Failed to change scene to %s" % scene_path)


func _play_button_press_sfx() -> void:
	_play_transient_sfx(BUTTON_PRESS_SFX)


func _play_player_move_sfx() -> void:
	_play_transient_sfx(PLAYER_MOVE_SFX)


func _play_transient_sfx(stream: AudioStream) -> void:
	if stream == null:
		return

	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var sfx_player: AudioStreamPlayer = AudioStreamPlayer.new()
	sfx_player.stream = stream
	sfx_player.finished.connect(sfx_player.queue_free)
	tree.root.add_child(sfx_player)
	sfx_player.play()


func _lock_title_overlay_hidden() -> void:
	_title_overlay_locked_hidden = true
	if title_overlay != null:
		title_overlay.hide()
		title_overlay.modulate.a = 0.0


func _should_start_in_active_state() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false

	if not tree.has_meta(START_IN_ACTIVE_STATE_META_KEY):
		return false

	tree.remove_meta(START_IN_ACTIVE_STATE_META_KEY)
	return true

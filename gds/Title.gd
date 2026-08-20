extends Node2D

const ENTRY_TILE_ATLAS: Vector2i = Vector2i(2, 0)
const REVEAL_DURATION: float = 1.0
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
@onready var title_overlay: Control = $CanvasLayer/ClearOverlay
@onready var start_button: Button = $CanvasLayer/ClearOverlay/CenterContainer/VBoxContainer/StartButton
@onready var exit_button: Button = $CanvasLayer/ClearOverlay/CenterContainer/VBoxContainer/ExitButton

var _is_starting: bool = false
var _is_entering_stage: bool = false
var _entry_cell_to_scene_path: Dictionary = {}


func _ready() -> void:
	if not start_button.pressed.is_connected(_on_start_button_pressed):
		start_button.pressed.connect(_on_start_button_pressed)
	if not exit_button.pressed.is_connected(_on_exit_button_pressed):
		exit_button.pressed.connect(_on_exit_button_pressed)
	if not player.move_finished.is_connected(_on_player_move_finished):
		player.move_finished.connect(_on_player_move_finished)

	_collect_stage_entry_cells()
	_set_reveal_state(0.0)


func _on_start_button_pressed() -> void:
	if _is_starting:
		return

	_is_starting = true
	start_button.disabled = true
	exit_button.disabled = true
	await _reveal_title_world()
	if player != null:
		player.controllable = true


func _on_exit_button_pressed() -> void:
	get_tree().quit()


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

	if title_overlay != null:
		title_overlay.modulate.a = 1.0 - clamped_alpha


func _reveal_title_world() -> void:
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_set_reveal_state, 0.0, 1.0, REVEAL_DURATION)
	await tween.finished
	if title_overlay != null:
		title_overlay.visible = false


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

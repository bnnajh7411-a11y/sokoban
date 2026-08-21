extends Node2D

const GOAL_ATLAS_COORD: Vector2i = Vector2i(2, 0)
const PLAYER_MOVE_SFX: AudioStream = preload("res://audios/u_2fbuaev0zn-select-sound-121244.mp3")
const BUTTON_PRESS_SFX: AudioStream = preload("res://audios/slodkabonanza-pop-sound-effect-197846.mp3")
const OVERLAP_SFX: AudioStream = preload("res://audios/freesound_community-cartoon-bite-39234.mp3")
const NEXT_STAGE_BUTTON_TEXT: String = "다음 스테이지"
const FINAL_STAGE_BUTTON_TEXT: String = "타이틀로"
const CLEAR_TITLE_TEXT: String = "클리어!"
const CLEAR_MESSAGE_TEXT: String = "목표 지점에 도착했습니다."
const GAME_OVER_TITLE_TEXT: String = "게임 오버"
const GAME_OVER_MESSAGE_TEXT: String = "플레이어와 양이 겹쳤습니다."
const SHEEP_GROUP_NAME: StringName = &"sheep"
const MOVE_COUNT_TEXT: String = "이동 횟수: %d"

@onready var tile_map_layer: TileMapLayer = $TileMapLayer
@onready var player: GridActor = $Player
@onready var undo_button: Button = get_node_or_null("CanvasLayer/Hud/UndoButton") as Button
@onready var hud_restart_button: Button = get_node_or_null("CanvasLayer/Hud/RetryButton") as Button
@onready var move_count_label: Label = $CanvasLayer/Hud/MoveCountLabel
@onready var sheep_alert_sfx: AudioStreamPlayer = $SheepAlertSfx
@onready var result_overlay: Control = $CanvasLayer/ClearOverlay
@onready var result_title_label: Label = $CanvasLayer/ClearOverlay/CenterContainer/ClearPanel/VBoxContainer/TitleLabel
@onready var result_message_label: Label = $CanvasLayer/ClearOverlay/CenterContainer/ClearPanel/VBoxContainer/MessageLabel
@onready var result_buttons_container: VBoxContainer = $CanvasLayer/ClearOverlay/CenterContainer/ClearPanel/VBoxContainer
@onready var next_button: Button = get_node_or_null("CanvasLayer/ClearOverlay/CenterContainer/ClearPanel/VBoxContainer/NextButton") as Button
@onready var restart_button: Button = $CanvasLayer/ClearOverlay/CenterContainer/ClearPanel/VBoxContainer/RetryButton
@onready var title_button: Button = get_node_or_null("CanvasLayer/ClearOverlay/CenterContainer/ClearPanel/VBoxContainer/TitleButton") as Button
@onready var tutorial_overlay: Node = get_node_or_null("CanvasLayer/TutorialOverlay")

var _goal_cells: Dictionary = {}
var _undo_history: Array = []
var _pending_undo_requests: int = 0
var _undo_chain_running: bool = false
var _pending_sheep_moves: int = 0
var _waiting_for_sheep: bool = false
var _player_move_count: int = 0
var _is_turn_active: bool = false
var _is_cleared: bool = false
var _is_game_over: bool = false
var _next_stage_path: String = ""


func _ready() -> void:
	_collect_goal_cells()
	_setup_clear_ui()
	_update_move_count_ui()
	call_deferred("_bind_turn_flow")
	_update_undo_button_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return

	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == KEY_Z or key_event.physical_keycode == KEY_Z:
		_handle_undo_shortcut()
	elif key_event.keycode == KEY_X or key_event.physical_keycode == KEY_X:
		_handle_retry_shortcut()


func _bind_turn_flow() -> void:
	_connect_actor(player)

	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		_connect_actor(node as GridActor)

	_prune_initial_sheep_state()
	_update_sheep_alert_states()
	if _has_player_sheep_overlap():
		_show_game_over_ui()
	elif not _has_active_sheep():
		_show_clear_ui()


func _connect_actor(actor: GridActor) -> void:
	if actor == null:
		return

	if not actor.move_started.is_connected(_on_actor_move_started):
		actor.move_started.connect(_on_actor_move_started)
	if not actor.move_finished.is_connected(_on_actor_move_finished):
		actor.move_finished.connect(_on_actor_move_finished)


func _setup_clear_ui() -> void:
	result_overlay.visible = false
	if next_button != null:
		next_button.visible = false
	result_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_configure_next_button()
	_ensure_title_button()
	if title_button != null:
		title_button.visible = false
	if hud_restart_button != null and not hud_restart_button.pressed.is_connected(_on_restart_button_pressed):
		hud_restart_button.pressed.connect(_on_restart_button_pressed)
	if not restart_button.pressed.is_connected(_on_restart_button_pressed):
		restart_button.pressed.connect(_on_restart_button_pressed)
	if next_button != null and not next_button.pressed.is_connected(_on_next_button_pressed):
		next_button.pressed.connect(_on_next_button_pressed)
	if title_button != null and not title_button.pressed.is_connected(_on_title_button_pressed):
		title_button.pressed.connect(_on_title_button_pressed)

	if undo_button != null:
		undo_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		undo_button.focus_mode = Control.FOCUS_NONE
		if not undo_button.pressed.is_connected(_on_undo_button_pressed):
			undo_button.pressed.connect(_on_undo_button_pressed)

	if hud_restart_button != null:
		hud_restart_button.focus_mode = Control.FOCUS_NONE
	if restart_button != null:
		restart_button.focus_mode = Control.FOCUS_NONE
	if title_button != null:
		title_button.focus_mode = Control.FOCUS_NONE

	_update_undo_button_ui()


func _update_move_count_ui() -> void:
	move_count_label.text = MOVE_COUNT_TEXT % _player_move_count


func _update_undo_button_ui() -> void:
	if undo_button == null:
		return

	undo_button.disabled = not _can_request_undo()


func _can_request_undo() -> bool:
	if _undo_history.is_empty():
		return false

	return _undo_chain_running or not (_is_turn_active or _has_active_motion())


func _capture_undo_state() -> void:
	var sheep_states: Dictionary = {}

	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: GridActor = node as GridActor
		if sheep != null:
			sheep_states[String(sheep.get_path())] = sheep.get_grid_state()

	_undo_history.append({
		"player": player.get_grid_state(),
		"sheep": sheep_states,
		"move_count": _player_move_count,
	})
	_update_undo_button_ui()


func _restore_undo_state(snapshot: Dictionary, animate: bool = false) -> float:
	var restore_duration: float = 0.0
	var player_state: Variant = snapshot.get("player")
	if player_state is Dictionary:
		restore_duration = max(restore_duration, player.restore_grid_state(player_state, animate))

	var sheep_states: Dictionary = snapshot.get("sheep", {})
	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: GridActor = node as GridActor
		if sheep == null:
			continue

		var sheep_state: Variant = sheep_states.get(String(sheep.get_path()))
		if sheep_state is Dictionary:
			restore_duration = max(restore_duration, sheep.restore_grid_state(sheep_state, animate))

	_player_move_count = int(snapshot.get("move_count", _player_move_count))
	_pending_sheep_moves = 0
	_waiting_for_sheep = false
	if not animate:
		_is_turn_active = false
	_is_cleared = false
	_is_game_over = false
	player.controllable = not animate
	result_overlay.visible = false
	_update_move_count_ui()
	_stop_sheep_alert_states()
	if not animate:
		_update_sheep_alert_states()
	_update_undo_button_ui()
	return restore_duration


func _collect_goal_cells() -> void:
	_goal_cells.clear()

	if tile_map_layer == null:
		return

	for cell in tile_map_layer.get_used_cells():
		if tile_map_layer.get_cell_atlas_coords(cell) == GOAL_ATLAS_COORD:
			_goal_cells[cell] = true


func _has_active_sheep() -> bool:
	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: SheepActor = node as SheepActor
		if sheep != null and not sheep.is_removed():
			return true

	return false


func _has_player_sheep_overlap() -> bool:
	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: SheepActor = node as SheepActor
		if sheep != null and not sheep.is_removed() and sheep.grid_cell == player.grid_cell:
			return true

	return false


func _prune_initial_sheep_state() -> void:
	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: SheepActor = node as SheepActor
		if sheep == null or sheep.is_removed():
			continue

		if _goal_cells.has(sheep.grid_cell):
			sheep.remove_from_board()


func _show_clear_ui() -> void:
	if _is_finished():
		return

	_is_cleared = true
	_is_turn_active = false
	player.controllable = false
	_stop_sheep_alert_states()
	result_title_label.text = CLEAR_TITLE_TEXT
	result_message_label.text = CLEAR_MESSAGE_TEXT
	result_overlay.visible = true
	if next_button != null:
		next_button.visible = true
	if title_button != null:
		title_button.visible = false
	_update_undo_button_ui()


func _show_game_over_ui() -> void:
	if _is_finished():
		return

	_play_overlap_sfx()
	_is_cleared = false
	_is_game_over = true
	_is_turn_active = false
	player.controllable = false
	_stop_sheep_alert_states()
	result_title_label.text = GAME_OVER_TITLE_TEXT
	result_message_label.text = GAME_OVER_MESSAGE_TEXT
	result_overlay.visible = true
	if next_button != null:
		next_button.visible = false
	if title_button != null:
		title_button.visible = true
	_update_undo_button_ui()


func _on_actor_move_started(actor: Node, _from_cell: Vector2i, _to_cell: Vector2i, _direction: Vector2i) -> void:
	if _is_finished():
		return

	if actor != player:
		return

	_play_player_move_sfx()
	_is_turn_active = true
	_capture_undo_state()
	_update_undo_button_ui()


func _on_actor_move_finished(actor: Node, from_cell: Vector2i, to_cell: Vector2i, _direction: Vector2i) -> void:
	if _is_finished():
		return

	if actor == player:
		_player_move_count += 1
		_update_move_count_ui()
		if _has_player_sheep_overlap():
			_show_game_over_ui()
			return
		_resolve_sheep_turn(from_cell, to_cell)
		_update_sheep_alert_states()
		_update_undo_button_ui()
		return

	var sheep_actor: SheepActor = actor as SheepActor
	if sheep_actor == null or sheep_actor.is_removed():
		return

	_pending_sheep_moves = max(_pending_sheep_moves - 1, 0)
	if to_cell == player.grid_cell:
		_show_game_over_ui()
		return

	if _goal_cells.has(to_cell):
		sheep_actor.remove_from_board()
		if not _has_active_sheep():
			_show_clear_ui()
			return

	if _pending_sheep_moves == 0 and _waiting_for_sheep:
		_waiting_for_sheep = false
		_is_turn_active = false
		player.consume_queued_direction()

	_update_sheep_alert_states()
	_update_undo_button_ui()


func _resolve_sheep_turn(wolf_from: Vector2i, wolf_to: Vector2i) -> void:
	if _is_finished():
		return

	_pending_sheep_moves = 0
	_waiting_for_sheep = false
	var should_play_alert_sound: bool = false

	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: SheepActor = node as SheepActor
		if sheep != null and not sheep.is_removed():
			if sheep.did_wolf_enter_alert_range(wolf_from, wolf_to):
				should_play_alert_sound = true
			if sheep.react_to_wolf_move(wolf_from, wolf_to):
				_pending_sheep_moves += 1

	if should_play_alert_sound:
		_play_sheep_alert_sound()

	if _pending_sheep_moves == 0:
		_is_turn_active = false
		player.consume_queued_direction()
	else:
		_waiting_for_sheep = true

	_update_undo_button_ui()


func _on_restart_button_pressed() -> void:
	if tutorial_overlay != null and tutorial_overlay.has_method("prepare_for_restart"):
		tutorial_overlay.call("prepare_for_restart")

	_play_button_press_sfx()
	get_tree().reload_current_scene()


func _on_next_button_pressed() -> void:
	if _next_stage_path.is_empty():
		return

	_play_button_press_sfx()
	if _next_stage_path.ends_with("Title.tscn"):
		_go_to_title_scene(true)
		return

	get_tree().change_scene_to_file(_next_stage_path)


func _on_title_button_pressed() -> void:
	_play_button_press_sfx()
	_go_to_title_scene(true)


func _on_undo_button_pressed() -> void:
	if not _can_request_undo():
		return

	_play_button_press_sfx()
	_pending_undo_requests = min(_pending_undo_requests + 1, _undo_history.size())
	_update_undo_button_ui()
	_schedule_undo_queue()


func _handle_undo_shortcut() -> void:
	if undo_button == null or undo_button.disabled:
		return

	_on_undo_button_pressed()
	get_viewport().set_input_as_handled()


func _handle_retry_shortcut() -> void:
	get_viewport().set_input_as_handled()
	_on_restart_button_pressed()


func _schedule_undo_queue() -> void:
	if _undo_chain_running:
		return

	_undo_chain_running = true
	call_deferred("_process_undo_queue")


func _process_undo_queue() -> void:
	_is_turn_active = true
	player.controllable = false
	_update_undo_button_ui()

	while _pending_undo_requests > 0 and not _undo_history.is_empty():
		_pending_undo_requests -= 1

		var snapshot: Dictionary = _undo_history.pop_back()
		var restore_duration: float = _restore_undo_state(snapshot, true)
		if restore_duration > 0.0:
			await get_tree().create_timer(restore_duration).timeout
			while _has_active_motion():
				await get_tree().process_frame

	_pending_undo_requests = 0

	player.controllable = true
	_is_turn_active = false
	_undo_chain_running = false
	_update_sheep_alert_states()
	_update_undo_button_ui()


func _update_sheep_alert_states() -> void:
	if _is_finished():
		return

	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: SheepActor = node as SheepActor
		if sheep != null and not sheep.is_removed():
			sheep.update_player_proximity(player.grid_cell)


func _stop_sheep_alert_states() -> void:
	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: SheepActor = node as SheepActor
		if sheep != null and not sheep.is_removed():
			sheep.stop_alert_shake()


func _is_sheep_actor(actor: Node) -> bool:
	return actor is GridActor and actor.is_in_group(SHEEP_GROUP_NAME)


func _has_active_motion() -> bool:
	if player.is_moving():
		return true

	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: GridActor = node as GridActor
		if sheep != null and sheep.is_moving():
			return true

	return false


func _is_finished() -> bool:
	return _is_cleared or _is_game_over


func _play_player_move_sfx() -> void:
	_play_transient_sfx(PLAYER_MOVE_SFX)


func _play_button_press_sfx() -> void:
	_play_transient_sfx(BUTTON_PRESS_SFX)


func _play_overlap_sfx() -> void:
	_play_transient_sfx(OVERLAP_SFX)


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




func _configure_next_button() -> void:
	_next_stage_path = _get_next_stage_path()
	if next_button == null:
		return

	next_button.visible = false
	if _next_stage_path.is_empty() or _next_stage_path.ends_with("Title.tscn"):
		next_button.text = FINAL_STAGE_BUTTON_TEXT
	else:
		next_button.text = NEXT_STAGE_BUTTON_TEXT


func _get_next_stage_path() -> String:
	if get_tree() == null or get_tree().current_scene == null:
		return ""

	var current_scene_path: String = String(get_tree().current_scene.scene_file_path)
	var current_scene_name: String = current_scene_path.get_file().trim_suffix(".tscn")
	if not current_scene_name.begins_with("Stage"):
		return "res://scenes/Title.tscn"

	var stage_number_text: String = current_scene_name.trim_prefix("Stage")
	if not stage_number_text.is_valid_int():
		return "res://scenes/Title.tscn"

	var next_stage_number: int = int(stage_number_text) + 1
	var next_stage_path: String = "res://scenes/Stage%d.tscn" % next_stage_number
	if ResourceLoader.exists(next_stage_path):
		return next_stage_path

	return "res://scenes/Title.tscn"


func _play_sheep_alert_sound() -> void:
	if sheep_alert_sfx == null:
		return

	sheep_alert_sfx.stop()
	sheep_alert_sfx.play()


func _ensure_title_button() -> void:
	if title_button != null:
		return
	if result_buttons_container == null:
		return

	title_button = Button.new()
	title_button.name = "TitleButton"
	title_button.custom_minimum_size = Vector2(120, 32)
	title_button.layout_mode = 2
	title_button.add_theme_font_size_override("font_size", 20)
	title_button.text = "타이틀로"
	title_button.visible = false
	result_buttons_container.add_child(title_button)
	if restart_button != null:
		result_buttons_container.move_child(title_button, restart_button.get_index() + 1)
	if not title_button.pressed.is_connected(_on_title_button_pressed):
		title_button.pressed.connect(_on_title_button_pressed)


func _go_to_title_scene(start_in_active_state: bool) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	if start_in_active_state:
		tree.set_meta("title_start_in_active_state", true)

	tree.change_scene_to_file("res://scenes/Title.tscn")

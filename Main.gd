extends Node2D

const GOAL_ATLAS_COORD: Vector2i = Vector2i(2, 0)
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
@onready var result_overlay: Control = $CanvasLayer/ClearOverlay
@onready var result_title_label: Label = $CanvasLayer/ClearOverlay/CenterContainer/ClearPanel/VBoxContainer/TitleLabel
@onready var result_message_label: Label = $CanvasLayer/ClearOverlay/CenterContainer/ClearPanel/VBoxContainer/MessageLabel
@onready var restart_button: Button = $CanvasLayer/ClearOverlay/CenterContainer/ClearPanel/VBoxContainer/RetryButton
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


func _ready() -> void:
	_collect_goal_cells()
	_setup_clear_ui()
	_update_move_count_ui()
	call_deferred("_bind_turn_flow")
	_update_sheep_alert_states()
	_update_undo_button_ui()
	_check_for_game_over()
	_check_for_clear()


func _bind_turn_flow() -> void:
	_connect_actor(player)

	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		_connect_actor(node as GridActor)

	_update_sheep_alert_states()


func _connect_actor(actor: GridActor) -> void:
	if actor == null:
		return

	if not actor.move_started.is_connected(_on_actor_move_started):
		actor.move_started.connect(_on_actor_move_started)
	if not actor.move_finished.is_connected(_on_actor_move_finished):
		actor.move_finished.connect(_on_actor_move_finished)


func _setup_clear_ui() -> void:
	result_overlay.visible = false
	result_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hud_restart_button != null and not hud_restart_button.pressed.is_connected(_on_restart_button_pressed):
		hud_restart_button.pressed.connect(_on_restart_button_pressed)
	if not restart_button.pressed.is_connected(_on_restart_button_pressed):
		restart_button.pressed.connect(_on_restart_button_pressed)

	if undo_button != null:
		undo_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		if not undo_button.pressed.is_connected(_on_undo_button_pressed):
			undo_button.pressed.connect(_on_undo_button_pressed)

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


func _check_for_clear() -> void:
	if _is_finished():
		return

	if _has_player_sheep_overlap():
		_show_game_over_ui()
		return

	if _has_sheep_on_goal():
		_show_clear_ui()


func _check_for_game_over() -> void:
	if _is_finished():
		return

	if _has_player_sheep_overlap():
		_show_game_over_ui()


func _has_player_sheep_overlap() -> bool:
	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: GridActor = node as GridActor
		if sheep != null and sheep.grid_cell == player.grid_cell:
			return true

	return false


func _has_sheep_on_goal() -> bool:
	if _goal_cells.is_empty():
		return false

	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: GridActor = node as GridActor
		if sheep != null and _goal_cells.has(sheep.grid_cell):
			return true

	return false


func _show_clear_ui() -> void:
	if _is_finished():
		return

	_is_cleared = true
	_is_game_over = false
	_is_turn_active = false
	player.controllable = false
	_stop_sheep_alert_states()
	result_title_label.text = CLEAR_TITLE_TEXT
	result_message_label.text = CLEAR_MESSAGE_TEXT
	result_overlay.visible = true
	restart_button.grab_focus()
	_update_undo_button_ui()


func _show_game_over_ui() -> void:
	if _is_finished():
		return

	_is_cleared = false
	_is_game_over = true
	_is_turn_active = false
	player.controllable = false
	_stop_sheep_alert_states()
	result_title_label.text = GAME_OVER_TITLE_TEXT
	result_message_label.text = GAME_OVER_MESSAGE_TEXT
	result_overlay.visible = true
	restart_button.grab_focus()
	_update_undo_button_ui()


func _on_actor_move_started(actor: Node, _from_cell: Vector2i, _to_cell: Vector2i, _direction: Vector2i) -> void:
	if _is_finished():
		return

	if actor != player:
		return

	_is_turn_active = true
	_capture_undo_state()
	_update_undo_button_ui()


func _on_actor_move_finished(actor: Node, from_cell: Vector2i, to_cell: Vector2i, _direction: Vector2i) -> void:
	if _is_finished():
		return

	if _has_player_sheep_overlap():
		_show_game_over_ui()
		return

	if actor == player:
		_player_move_count += 1
		_update_move_count_ui()
		_resolve_sheep_turn(from_cell, to_cell)
		_update_sheep_alert_states()
		_update_undo_button_ui()
		return

	if not _is_sheep_actor(actor):
		return

	_pending_sheep_moves = max(_pending_sheep_moves - 1, 0)
	if _has_player_sheep_overlap():
		_show_game_over_ui()
		return

	if _has_sheep_on_goal():
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

	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: GridActor = node as GridActor
		if sheep != null and sheep.react_to_wolf_move(wolf_from, wolf_to):
			_pending_sheep_moves += 1

	if _pending_sheep_moves == 0:
		_is_turn_active = false
		player.consume_queued_direction()
	else:
		_waiting_for_sheep = true

	_update_undo_button_ui()


func _on_restart_button_pressed() -> void:
	if tutorial_overlay != null and tutorial_overlay.has_method("prepare_for_restart"):
		tutorial_overlay.call("prepare_for_restart")

	get_tree().reload_current_scene()


func _on_undo_button_pressed() -> void:
	if not _can_request_undo():
		return

	_pending_undo_requests = min(_pending_undo_requests + 1, _undo_history.size())
	_update_undo_button_ui()
	_schedule_undo_queue()


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
		if sheep != null:
			sheep.update_player_proximity(player.grid_cell)


func _stop_sheep_alert_states() -> void:
	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: SheepActor = node as SheepActor
		if sheep != null:
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

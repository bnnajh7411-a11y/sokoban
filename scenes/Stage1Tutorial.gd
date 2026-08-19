extends Control

const SHEEP_GROUP_NAME: StringName = &"sheep"
const OPENING_BODY_TEXT: String = "방향키로 늑대를 움직여 보세요."
const SHEEP_HINT_TEXT: String = "양은 늑대가 가까이 오면 도망가요."
const UNDO_HINT_TEXT: String = "실수하면 왼쪽 위 실행취소나 초기화 버튼으로 되돌릴 수 있어요."
const GOAL_HINT_TEXT: String = "양을 진한 초록 칸으로 유도해 보세요."
const SIGHT_ALERT_RANGE_TILES: int = 1
const TIP_DURATION_SECONDS: float = 3.2

static var _pending_restore_state: Dictionary = {}

@onready var message_overlay: Control = $MessageOverlay
@onready var message_label: Label = $MessageOverlay/CenterContainer/TutorialPanel/MarginContainer/MessageLabel
@onready var sight: CanvasItem = get_node_or_null("../../Sight") as CanvasItem
@onready var highlight: CanvasItem = get_node_or_null("../../Highlight") as CanvasItem
@onready var player: GridActor = get_node_or_null("../../Player") as GridActor
@onready var undo_button: Button = get_node_or_null("../Hud/UndoButton") as Button
@onready var clear_overlay: Control = get_node_or_null("../ClearOverlay") as Control

var _has_hidden_opening: bool = false
var _has_shown_sheep_hint: bool = false
var _has_queued_goal_hint: bool = false
var _is_showing_tip: bool = false
var _is_waiting_for_undo_action: bool = false
var _current_tip_message: String = ""
var _tip_queue: Array[String] = []
var _tip_run_id: int = 0


func _ready() -> void:
	_show_opening_message()

	if sight != null:
		sight.visible = false
	if highlight != null:
		highlight.visible = false

	_restore_pending_restart_state()

	if clear_overlay != null and not clear_overlay.visibility_changed.is_connected(_on_clear_overlay_visibility_changed):
		clear_overlay.visibility_changed.connect(_on_clear_overlay_visibility_changed)

	call_deferred("_bind_tutorial_signals")


func _bind_tutorial_signals() -> void:
	if player != null and not player.move_started.is_connected(_on_player_move_started):
		player.move_started.connect(_on_player_move_started)
	if player != null and not player.move_finished.is_connected(_on_player_move_finished):
		player.move_finished.connect(_on_player_move_finished)

	if undo_button != null and not undo_button.pressed.is_connected(_on_undo_button_pressed):
		undo_button.pressed.connect(_on_undo_button_pressed)

	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: SheepActor = node as SheepActor
		if sheep != null and not sheep.move_started.is_connected(_on_sheep_move_started):
			sheep.move_started.connect(_on_sheep_move_started)


func _on_player_move_started(_actor: Node, _from_cell: Vector2i, _to_cell: Vector2i, _direction: Vector2i) -> void:
	_hide_opening()


func _on_player_move_finished(_actor: Node, _from_cell: Vector2i, _to_cell: Vector2i, _direction: Vector2i) -> void:
	if _is_level_finished():
		return

	if not _has_shown_sheep_hint:
		_has_shown_sheep_hint = true
		_enqueue_tip(SHEEP_HINT_TEXT)

	_update_tip_visuals(_current_tip_message)


func _on_sheep_move_started(_actor: Node, _from_cell: Vector2i, _to_cell: Vector2i, _direction: Vector2i) -> void:
	if _is_level_finished():
		return

	_hide_opening()
	_update_tip_visuals(_current_tip_message)

	if _current_tip_message == SHEEP_HINT_TEXT:
		_dismiss_current_tip(false)

	if not _has_shown_sheep_hint:
		_has_shown_sheep_hint = true
		_enqueue_tip(SHEEP_HINT_TEXT)

	if not _has_queued_goal_hint:
		_has_queued_goal_hint = true
		_enqueue_tip(UNDO_HINT_TEXT)
		_enqueue_tip(GOAL_HINT_TEXT)


func _on_undo_button_pressed() -> void:
	if _is_level_finished():
		return

	_hide_opening()
	if _dismiss_undo_hint():
		return

	if _has_queued_goal_hint:
		return

	_has_queued_goal_hint = true
	_enqueue_tip(UNDO_HINT_TEXT)
	_enqueue_tip(GOAL_HINT_TEXT)


func _enqueue_tip(message: String) -> void:
	if message.is_empty() or _is_level_finished():
		return

	if _tip_queue.has(message):
		return

	_tip_queue.append(message)
	if _is_showing_tip:
		return

	_show_next_tip()


func _show_next_tip() -> void:
	if _tip_queue.is_empty() or _is_level_finished():
		_is_showing_tip = false
		_hide_message()
		return

	_is_showing_tip = true
	_is_waiting_for_undo_action = false
	_set_player_input_locked(false)

	var message: String = String(_tip_queue.pop_front())
	_current_tip_message = message
	message_label.text = message
	message_overlay.visible = true
	_update_tip_visuals(message)

	if message == SHEEP_HINT_TEXT:
		return

	if message == UNDO_HINT_TEXT:
		_is_waiting_for_undo_action = true
		_set_player_input_locked(true)
		return

	_tip_run_id += 1
	_hide_tip_later(_tip_run_id)


func _hide_tip_later(run_id: int) -> void:
	await get_tree().create_timer(TIP_DURATION_SECONDS).timeout

	if run_id != _tip_run_id:
		return

	_dismiss_current_tip()


func _hide_opening() -> void:
	if _has_hidden_opening:
		return

	_has_hidden_opening = true
	if not _is_showing_tip:
		_hide_message()


func prepare_for_restart() -> void:
	if _is_level_finished():
		return

	var saved_tip_queue: Array[String] = _tip_queue.duplicate()
	var current_tip: String = _current_tip_message
	var is_waiting_for_undo_action: bool = _is_waiting_for_undo_action
	var is_showing_tip: bool = _is_showing_tip and not current_tip.is_empty()

	if current_tip == UNDO_HINT_TEXT:
		current_tip = ""
		is_waiting_for_undo_action = false
		is_showing_tip = false
		if _has_queued_goal_hint and not saved_tip_queue.has(GOAL_HINT_TEXT):
			saved_tip_queue.push_front(GOAL_HINT_TEXT)

	_pending_restore_state = {
		"has_hidden_opening": _has_hidden_opening,
		"has_shown_sheep_hint": _has_shown_sheep_hint,
		"has_queued_goal_hint": _has_queued_goal_hint,
		"current_tip": current_tip,
		"is_showing_tip": is_showing_tip,
		"is_waiting_for_undo_action": is_waiting_for_undo_action,
		"tip_queue": saved_tip_queue,
	}


func _restore_pending_restart_state() -> void:
	if _pending_restore_state.is_empty():
		return

	var state: Dictionary = _pending_restore_state
	_pending_restore_state = {}

	_has_hidden_opening = bool(state.get("has_hidden_opening", false))
	_has_shown_sheep_hint = bool(state.get("has_shown_sheep_hint", false))
	_has_queued_goal_hint = bool(state.get("has_queued_goal_hint", false))
	_current_tip_message = String(state.get("current_tip", ""))
	_is_showing_tip = bool(state.get("is_showing_tip", false))
	_is_waiting_for_undo_action = bool(state.get("is_waiting_for_undo_action", false))

	var saved_tip_queue: Variant = state.get("tip_queue", [])
	if saved_tip_queue is Array:
		_tip_queue = saved_tip_queue.duplicate()
	else:
		_tip_queue = []

	if not _is_showing_tip or _current_tip_message.is_empty():
		if _has_hidden_opening:
			_hide_message()
		else:
			_show_opening_message()
		_update_tip_visuals("")
		if not _tip_queue.is_empty():
			_show_next_tip()
		return

	message_label.text = _current_tip_message
	message_overlay.visible = true
	_update_tip_visuals(_current_tip_message)

	if _is_waiting_for_undo_action:
		_set_player_input_locked(true)
		return

	if _current_tip_message == SHEEP_HINT_TEXT:
		return

	_tip_run_id += 1
	_hide_tip_later(_tip_run_id)


func _dismiss_undo_hint() -> bool:
	if not _is_waiting_for_undo_action or _current_tip_message != UNDO_HINT_TEXT:
		return false

	_dismiss_current_tip()
	return true


func _on_clear_overlay_visibility_changed() -> void:
	if clear_overlay == null or not clear_overlay.visible:
		return

	_hide_all_tutorial()


func _hide_all_tutorial() -> void:
	_hide_opening()
	_tip_queue.clear()
	_is_waiting_for_undo_action = false
	_set_player_input_locked(false)
	_is_showing_tip = false
	_tip_run_id += 1
	_current_tip_message = ""
	_hide_message()
	_update_tip_visuals("")


func _is_level_finished() -> bool:
	return clear_overlay != null and clear_overlay.visible


func _show_opening_message() -> void:
	message_label.text = OPENING_BODY_TEXT
	message_overlay.visible = true


func _hide_message() -> void:
	message_overlay.visible = false


func _update_tip_visuals(message: String) -> void:
	if sight != null:
		sight.visible = message == SHEEP_HINT_TEXT and not _is_player_in_sight_range()

	if highlight != null:
		highlight.visible = message == UNDO_HINT_TEXT


func _dismiss_current_tip(show_next_tip: bool = true) -> void:
	var was_waiting_for_undo_action: bool = _is_waiting_for_undo_action

	_is_waiting_for_undo_action = false
	if was_waiting_for_undo_action:
		_set_player_input_locked(false)

	_current_tip_message = ""
	_hide_message()
	_update_tip_visuals("")
	_is_showing_tip = false

	if show_next_tip and not _tip_queue.is_empty():
		_show_next_tip()


func _set_player_input_locked(locked: bool) -> void:
	if player == null:
		return

	if locked:
		player.controllable = false
	elif not _is_level_finished():
		player.controllable = true


func _is_player_in_sight_range() -> bool:
	if player == null:
		return false

	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: SheepActor = node as SheepActor
		if sheep == null:
			continue

		var delta: Vector2i = player.grid_cell - sheep.grid_cell
		if max(abs(delta.x), abs(delta.y)) <= SIGHT_ALERT_RANGE_TILES:
			return true

	return false

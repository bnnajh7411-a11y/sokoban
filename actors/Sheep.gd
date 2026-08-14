class_name SheepActor
extends GridActor

const SHEEP_GROUP_NAME: StringName = &"sheep"
const ALERT_RANGE_TILES: int = 1
const ALERT_SHAKE_DISTANCE: float = 1.5
const ALERT_SHAKE_SPEED: float = 24.0

var _alert_active: bool = false
var _alert_time: float = 0.0
var _alert_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group(SHEEP_GROUP_NAME)
	set_process(true)
	super._ready()


func _process(delta: float) -> void:
	if not _alert_active or _is_moving:
		return

	_alert_time += delta
	_alert_offset = Vector2(
		sin(_alert_time * ALERT_SHAKE_SPEED),
		cos(_alert_time * (ALERT_SHAKE_SPEED * 1.37))
	) * ALERT_SHAKE_DISTANCE
	_refresh_sprite_visuals()


func react_to_wolf_move(wolf_from: Vector2i, wolf_to: Vector2i) -> bool:
	if _is_moving:
		return false

	if not _is_wolf_in_range(wolf_to):
		return false

	if _should_ignore_diagonal_step_from_cardinal(wolf_from, wolf_to):
		return false

	var flee_direction: Vector2i = _choose_flee_direction(wolf_from, wolf_to)
	if flee_direction == Vector2i.ZERO:
		return false

	return move_on_grid(flee_direction)


func update_player_proximity(player_cell: Vector2i) -> void:
	if _is_moving:
		_stop_alert_shake()
		return

	if _is_player_in_alert_range(player_cell):
		_start_alert_shake()
	else:
		_stop_alert_shake()


func stop_alert_shake() -> void:
	_stop_alert_shake()


func _is_wolf_in_range(wolf_cell: Vector2i) -> bool:
	var delta: Vector2i = wolf_cell - grid_cell
	return max(abs(delta.x), abs(delta.y)) <= 1


func _should_ignore_diagonal_step_from_cardinal(wolf_from: Vector2i, wolf_to: Vector2i) -> bool:
	var delta_to: Vector2i = wolf_to - grid_cell
	if abs(delta_to.x) != 1 or abs(delta_to.y) != 1:
		return false

	var delta_from: Vector2i = wolf_from - grid_cell
	return abs(delta_from.x) + abs(delta_from.y) == 1


func _choose_flee_direction(wolf_from: Vector2i, wolf_to: Vector2i) -> Vector2i:
	var offset: Vector2i = wolf_to - grid_cell
	if offset.x == 0 and abs(offset.y) == 1:
		return Vector2i(0, -offset.y)
	if offset.y == 0 and abs(offset.x) == 1:
		return Vector2i(-offset.x, 0)

	var approach: Vector2i = wolf_to - wolf_from
	if approach == Vector2i.ZERO:
		return Vector2i.ZERO

	if abs(approach.x) >= abs(approach.y):
		if approach.x > 0:
			return Vector2i.RIGHT
		if approach.x < 0:
			return Vector2i.LEFT

	if approach.y > 0:
		return Vector2i.DOWN
	if approach.y < 0:
		return Vector2i.UP

	return Vector2i.ZERO


func _is_player_in_alert_range(player_cell: Vector2i) -> bool:
	var delta: Vector2i = player_cell - grid_cell
	return max(abs(delta.x), abs(delta.y)) <= ALERT_RANGE_TILES


func _start_alert_shake() -> void:
	if _alert_active:
		return

	_alert_active = true
	_alert_time = 0.0


func _stop_alert_shake() -> void:
	if not _alert_active and _alert_offset == Vector2.ZERO:
		return

	_alert_active = false
	_alert_time = 0.0
	_alert_offset = Vector2.ZERO
	_refresh_sprite_visuals()


func _on_move_started() -> void:
	_stop_alert_shake()


func _refresh_sprite_visuals() -> void:
	sprite.position = _jump_offset + _block_offset + _alert_offset

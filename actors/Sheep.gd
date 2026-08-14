class_name SheepActor
extends GridActor

const SHEEP_GROUP_NAME: StringName = &"sheep"


func _ready() -> void:
	add_to_group(SHEEP_GROUP_NAME)
	super._ready()


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

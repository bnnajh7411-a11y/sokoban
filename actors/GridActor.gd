class_name GridActor
extends CharacterBody2D

@export var tile_map_path: NodePath = NodePath("../TileMapLayer")
@export var cell_size: int = 32
@export var move_duration: float = 0.12
@export var jump_height: float = 6.0
@export var block_bump_distance: float = 3.0
@export var block_bump_duration: float = 0.08
@export var controllable: bool = false

const SOLID_CUSTOM_DATA_NAME: String = "solid"
const LEGACY_WALL_ATLAS_COORD: Vector2i = Vector2i(1, 0)

@onready var sprite: Sprite2D = $Sprite2D
@onready var sprite_base_scale: Vector2 = $Sprite2D.scale

var tile_map_layer: TileMapLayer
var grid_cell: Vector2i
var _is_moving: bool = false
var _move_tween: Tween
var _jump_tween: Tween
var _feedback_tween: Tween
var _jump_offset: Vector2 = Vector2.ZERO
var _block_offset: Vector2 = Vector2.ZERO
var _queued_direction: Vector2i = Vector2i.ZERO


func _ready() -> void:
	tile_map_layer = get_node_or_null(tile_map_path) as TileMapLayer
	grid_cell = _world_to_cell(global_position)
	_snap_to_cell(grid_cell)
	_refresh_sprite_visuals()


func _unhandled_input(event: InputEvent) -> void:
	if not controllable or event.is_echo():
		return

	var direction := _get_direction_from_input(event)
	if direction == Vector2i.ZERO:
		return

	if _is_moving:
		_queued_direction = direction
		_update_facing(direction)
		return

	move_on_grid(direction)


func move_on_grid(direction: Vector2i) -> bool:
	if direction == Vector2i.ZERO:
		return false

	if _is_moving:
		_queued_direction = direction
		return false

	var next_cell: Vector2i = grid_cell + direction
	if not _can_enter(next_cell):
		_update_facing(direction)
		_play_block_feedback(direction)
		return false

	_queued_direction = Vector2i.ZERO
	_update_facing(direction)
	grid_cell = next_cell
	_move_to_cell(grid_cell)
	return true


func _can_enter(cell: Vector2i) -> bool:
	if tile_map_layer == null:
		return true

	var tile_data: TileData = tile_map_layer.get_cell_tile_data(cell)
	if tile_data == null:
		return _is_legacy_walkable(cell)

	if tile_data.has_custom_data(SOLID_CUSTOM_DATA_NAME):
		var solid: Variant = tile_data.get_custom_data(SOLID_CUSTOM_DATA_NAME)
		if solid is bool:
			return not solid
		return not bool(solid)

	return _is_legacy_walkable(cell)


func _is_legacy_walkable(cell: Vector2i) -> bool:
	if tile_map_layer == null:
		return true

	return tile_map_layer.get_cell_source_id(cell) != -1 and tile_map_layer.get_cell_atlas_coords(cell) != LEGACY_WALL_ATLAS_COORD


func _move_to_cell(cell: Vector2i) -> void:
	_is_moving = true

	var target_position: Vector2 = _cell_to_world(cell)

	if _move_tween != null:
		_move_tween.kill()
	if _jump_tween != null:
		_jump_tween.kill()
	if _feedback_tween != null:
		_feedback_tween.kill()
		_block_offset = Vector2.ZERO
		_refresh_sprite_visuals()

	_move_tween = create_tween()
	_move_tween.set_trans(Tween.TRANS_SINE)
	_move_tween.set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "global_position", target_position, move_duration)
	_move_tween.finished.connect(_on_move_tween_finished)

	_jump_tween = create_tween()
	_jump_tween.tween_method(_set_jump_progress, 0.0, 1.0, move_duration)
	_jump_tween.finished.connect(_on_jump_tween_finished)


func _snap_to_cell(cell: Vector2i) -> void:
	global_position = _cell_to_world(cell)
	_jump_offset = Vector2.ZERO
	_block_offset = Vector2.ZERO
	sprite.position = Vector2.ZERO
	sprite.scale = sprite_base_scale
	sprite.flip_h = false


func _world_to_cell(world_position: Vector2) -> Vector2i:
	if tile_map_layer != null:
		return tile_map_layer.local_to_map(tile_map_layer.to_local(world_position))

	return Vector2i(
		floori(world_position.x / float(cell_size)),
		floori(world_position.y / float(cell_size))
	)


func _cell_to_world(cell: Vector2i) -> Vector2:
	if tile_map_layer != null:
		return tile_map_layer.to_global(tile_map_layer.map_to_local(cell))

	return Vector2(
		cell.x * cell_size + cell_size * 0.5,
		cell.y * cell_size + cell_size * 0.5
	)


func _on_move_tween_finished() -> void:
	_is_moving = false
	_move_tween = null
	_jump_offset = Vector2.ZERO
	_refresh_sprite_visuals()
	_consume_queued_direction()


func _set_jump_progress(progress: float) -> void:
	var offset: float = jump_height * sin(progress * PI)
	_jump_offset = Vector2(0.0, -offset)

	var pulse: float = sin(progress * PI)
	sprite.scale = sprite_base_scale * Vector2(1.0 + 0.10 * pulse, 1.0 - 0.08 * pulse)
	_refresh_sprite_visuals()


func _on_jump_tween_finished() -> void:
	_jump_tween = null
	sprite.scale = sprite_base_scale
	_refresh_sprite_visuals()


func _get_direction_from_input(event: InputEvent) -> Vector2i:
	if event.is_action_pressed("ui_right"):
		return Vector2i.RIGHT
	if event.is_action_pressed("ui_left"):
		return Vector2i.LEFT
	if event.is_action_pressed("ui_down"):
		return Vector2i.DOWN
	if event.is_action_pressed("ui_up"):
		return Vector2i.UP

	return Vector2i.ZERO


func _update_facing(direction: Vector2i) -> void:
	if direction == Vector2i.ZERO:
		return

	if direction.x > 0:
		sprite.flip_h = false
	elif direction.x < 0:
		sprite.flip_h = true


func _refresh_sprite_visuals() -> void:
	sprite.position = _jump_offset + _block_offset


func _play_block_feedback(direction: Vector2i) -> void:
	var bump_direction: Vector2 = Vector2(direction)
	if bump_direction == Vector2.ZERO:
		return

	if _feedback_tween != null:
		_feedback_tween.kill()

	_feedback_tween = create_tween()
	_feedback_tween.set_trans(Tween.TRANS_SINE)
	_feedback_tween.set_ease(Tween.EASE_OUT)
	var half_duration: float = block_bump_duration * 0.5
	_feedback_tween.tween_method(_set_block_offset, Vector2.ZERO, bump_direction * block_bump_distance, half_duration)
	_feedback_tween.tween_method(_set_block_offset, bump_direction * block_bump_distance, Vector2.ZERO, half_duration)
	_feedback_tween.finished.connect(_on_feedback_tween_finished)


func _set_block_offset(offset: Vector2) -> void:
	_block_offset = offset
	_refresh_sprite_visuals()


func _consume_queued_direction() -> void:
	if _queued_direction == Vector2i.ZERO:
		return

	var direction: Vector2i = _queued_direction
	_queued_direction = Vector2i.ZERO
	move_on_grid(direction)


func _on_feedback_tween_finished() -> void:
	_feedback_tween = null
	_refresh_sprite_visuals()

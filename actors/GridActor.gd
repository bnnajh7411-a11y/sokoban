class_name GridActor
extends CharacterBody2D

@export var tile_map_path: NodePath = NodePath("../TileMapLayer")
@export var cell_size: int = 32
@export var controllable: bool = false

var tile_map_layer: TileMapLayer
var grid_cell: Vector2i


func _ready() -> void:
	tile_map_layer = get_node_or_null(tile_map_path) as TileMapLayer
	grid_cell = _world_to_cell(global_position)
	_snap_to_cell(grid_cell)


func _unhandled_input(event: InputEvent) -> void:
	if not controllable or event.is_echo():
		return

	var direction := Vector2i.ZERO

	if event.is_action_pressed("ui_right"):
		direction = Vector2i.RIGHT
	elif event.is_action_pressed("ui_left"):
		direction = Vector2i.LEFT
	elif event.is_action_pressed("ui_down"):
		direction = Vector2i.DOWN
	elif event.is_action_pressed("ui_up"):
		direction = Vector2i.UP

	if direction != Vector2i.ZERO:
		move_on_grid(direction)


func move_on_grid(direction: Vector2i) -> bool:
	var next_cell := grid_cell + direction
	if not _can_enter(next_cell):
		return false

	grid_cell = next_cell
	_snap_to_cell(grid_cell)
	return true


func _can_enter(cell: Vector2i) -> bool:
	if tile_map_layer == null:
		return true

	var source_id := tile_map_layer.get_cell_source_id(cell)
	if source_id == -1:
		return false

	return tile_map_layer.get_cell_atlas_coords(cell) != Vector2i(1, 0)


func _snap_to_cell(cell: Vector2i) -> void:
	global_position = Vector2(
		cell.x * cell_size + cell_size * 0.5,
		cell.y * cell_size + cell_size * 0.5
	)


func _world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		int(world_position.x / cell_size),
		int(world_position.y / cell_size)
	)

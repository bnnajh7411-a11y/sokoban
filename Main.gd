extends Node2D

const SHEEP_GROUP_NAME: StringName = &"sheep"

@onready var player: GridActor = $Player

var _pending_sheep_moves: int = 0
var _waiting_for_sheep: bool = false


func _ready() -> void:
	call_deferred("_bind_turn_flow")


func _bind_turn_flow() -> void:
	_connect_actor(player)

	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		_connect_actor(node as GridActor)


func _connect_actor(actor: GridActor) -> void:
	if actor == null:
		return

	if not actor.move_finished.is_connected(_on_actor_move_finished):
		actor.move_finished.connect(_on_actor_move_finished)


func _on_actor_move_finished(actor: Node, from_cell: Vector2i, to_cell: Vector2i, _direction: Vector2i) -> void:
	if actor == player:
		_resolve_sheep_turn(from_cell, to_cell)
		return

	if not _is_sheep_actor(actor):
		return

	_pending_sheep_moves = max(_pending_sheep_moves - 1, 0)
	if _pending_sheep_moves == 0 and _waiting_for_sheep:
		_waiting_for_sheep = false
		player.consume_queued_direction()


func _resolve_sheep_turn(wolf_from: Vector2i, wolf_to: Vector2i) -> void:
	_pending_sheep_moves = 0
	_waiting_for_sheep = false

	for node in get_tree().get_nodes_in_group(SHEEP_GROUP_NAME):
		var sheep: GridActor = node as GridActor
		if sheep != null and sheep.react_to_wolf_move(wolf_from, wolf_to):
			_pending_sheep_moves += 1

	if _pending_sheep_moves == 0:
		player.consume_queued_direction()
	else:
		_waiting_for_sheep = true


func _is_sheep_actor(actor: Node) -> bool:
	return actor is GridActor and actor.is_in_group(SHEEP_GROUP_NAME)

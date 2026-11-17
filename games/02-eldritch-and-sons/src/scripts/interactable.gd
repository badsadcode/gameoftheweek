## interactable.gd : glue for "look at it and press E" objects built from callables.
## The player's ray finds any collider with meta "interact" and calls prompt()/use() on it.
## (Shelves and crates implement the same four methods themselves.)
class_name Interactable
extends Node3D

var prompt_fn: Callable
var use_fn: Callable
var alt_prompt_fn: Callable
var alt_use_fn: Callable

static func make(parent: Node3D, pos: Vector3, size: Vector3, p_fn: Callable, u_fn: Callable) -> Interactable:
	var it := Interactable.new()
	it.position = pos
	it.prompt_fn = p_fn
	it.use_fn = u_fn
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.set_meta("interact", it)
	it.add_child(body)
	parent.add_child(it)
	return it

func prompt(game) -> String:
	return prompt_fn.call(game) if prompt_fn.is_valid() else ""

func use(game) -> void:
	if use_fn.is_valid(): use_fn.call(game)

func prompt_alt(game) -> String:
	return alt_prompt_fn.call(game) if alt_prompt_fn.is_valid() else ""

func use_alt(game) -> void:
	if alt_use_fn.is_valid(): alt_use_fn.call(game)

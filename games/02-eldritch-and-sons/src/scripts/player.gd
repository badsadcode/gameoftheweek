## player.gd : first-person shopkeeper. WASD + mouse, E use, R alternate, Q put a box down.
class_name Player
extends CharacterBody3D

const SPEED := 4.2
const SPRINT := 6.0
const GRAVITY := 18.0
const REACH := 3.0

var game
var cam: Camera3D
var hand: Node3D
var ray: RayCast3D
var held: Crate = null
var look_target = null      # interactable under the crosshair
var sensitivity := 0.0025
var bob := 0.0
var step_t := 0.0
var frozen := false          # menus / cutscenes

func setup(g) -> void:
	game = g
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	cam = Camera3D.new()
	cam.position = Vector3(0, 1.62, 0)
	cam.fov = 75
	cam.near = 0.05
	cam.current = true
	add_child(cam)
	hand = Node3D.new()
	hand.position = Vector3(0.0, -0.45, -0.75)
	cam.add_child(hand)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -REACH)
	ray.collide_with_bodies = true
	cam.add_child(ray)
	ray.add_exception(self)

func _unhandled_input(e: InputEvent) -> void:
	if frozen: return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= e.relative.x * sensitivity
		cam.rotation.x = clampf(cam.rotation.x - e.relative.y * sensitivity, -1.45, 1.45)

func _physics_process(dt: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * dt
	var dir := Vector3.ZERO
	if not frozen:
		var input := Input.get_vector("left", "right", "forward", "back")
		dir = (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var spd := SPRINT if Input.is_action_pressed("sprint") else SPEED
	velocity.x = lerpf(velocity.x, dir.x * spd, minf(1.0, dt * 12.0))
	velocity.z = lerpf(velocity.z, dir.z * spd, minf(1.0, dt * 12.0))
	move_and_slide()
	# head bob + footsteps
	var hs := Vector2(velocity.x, velocity.z).length()
	if hs > 0.5 and is_on_floor():
		bob += dt * hs * 2.2
		step_t -= dt * hs
		if step_t <= 0.0:
			step_t = 1.6
			Sfx.play("step", 0.35, randf_range(0.9, 1.1))
	cam.position.y = lerpf(cam.position.y, 1.62 + sin(bob * 2.0) * 0.035 * minf(1.0, hs / SPEED), minf(1.0, dt * 10.0))
	hand.position.y = -0.45 + sin(bob) * 0.02
	_update_look()

func _update_look() -> void:
	look_target = null
	if frozen: return
	ray.force_raycast_update()
	if ray.is_colliding():
		var c := ray.get_collider()
		if c and c.has_meta("interact"):
			look_target = c.get_meta("interact")

func current_prompt() -> String:
	if look_target == null or not is_instance_valid(look_target):
		return "[Q] Put the box down" if held else ""
	var p: String = look_target.prompt(game)
	var a := ""
	if look_target.has_method("prompt_alt"):
		a = look_target.prompt_alt(game)
	if a != "": p = (p + "\n" + a) if p != "" else a
	return p

func interact() -> void:
	if frozen or look_target == null or not is_instance_valid(look_target): return
	look_target.use(game)

func interact_alt() -> void:
	if frozen or look_target == null or not is_instance_valid(look_target): return
	if look_target.has_method("use_alt"): look_target.use_alt(game)

func pick_up(c: Crate) -> void:
	if held: return
	held = c
	c.set_held(true)
	c.get_parent().remove_child(c)
	hand.add_child(c)
	c.position = Vector3(0, -0.15, 0)
	c.rotation = Vector3.ZERO
	Sfx.play("box", 0.6, 1.2)

func put_down() -> void:
	if held == null: return
	var c := held
	held = null
	hand.remove_child(c)
	game.world.add_child(c)
	var fwd := -global_transform.basis.z
	fwd.y = 0
	c.global_position = global_position + fwd.normalized() * 0.9
	c.global_position.y = 0.0 if global_position.y < 0.5 else global_position.y
	c.rotation = Vector3(0, rotation.y, 0)
	c.set_held(false)
	Sfx.play("box", 0.7)

## the crate in your hands is empty: fold it away
func drop_empty() -> void:
	if held == null: return
	var c := held
	held = null
	c.queue_free()
	Sfx.play("box", 0.4, 1.6)

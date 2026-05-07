extends CharacterBody3D

@export var look_speed : float = 0.002
@export var move_speed : float = 10.0

@export_group("Input Actions")
@export var input_left : String = "ui_left"
@export var input_right : String = "ui_right"
@export var input_forward : String = "ui_up"
@export var input_back : String = "ui_down"

var mouse_captured : bool = false
var look_rotation : Vector2

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/SpringArm3D/Camera3D

func _ready():
	look_rotation.y = rotation.y
	look_rotation.x = head.rotation.x

func _unhandled_input(event: InputEvent) -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		capture_mouse()
	if Input.is_key_pressed(KEY_ESCAPE):
		release_mouse()

	if mouse_captured and event is InputEventMouseMotion:
		rotate_look(event.relative)

func _physics_process(delta: float) -> void:
	handle_movement()
	move_and_slide()

# =========================
# 🚀 MOVIMENTO (BASEADO NA CAMERA)
# =========================
func handle_movement():
	var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)

	# pega DIREÇÃO REAL da câmera
	var forward := camera.global_transform.basis.z
	var right := camera.global_transform.basis.x

	var move_dir := (right * input_dir.x + forward * input_dir.y).normalized()

	if move_dir != Vector3.ZERO:
		velocity = move_dir * move_speed
	else:
		velocity = velocity.move_toward(Vector3.ZERO, move_speed)

# =========================
# 🖱️ LOOK (CAMERA DE VERDADE)
# =========================
func rotate_look(rot_input : Vector2):
	look_rotation.x -= rot_input.y * look_speed
	look_rotation.x = clamp(look_rotation.x, deg_to_rad(-85), deg_to_rad(85))

	look_rotation.y -= rot_input.x * look_speed

	# gira corpo (Y)
	rotation.y = look_rotation.y

	# gira head (X)
	head.rotation = Vector3(look_rotation.x, 0, 0)

# =========================
# 🖱️ MOUSE
# =========================
func capture_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true

func release_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false

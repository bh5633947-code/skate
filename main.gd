extends Node3D

# ---------- Ajustes de física (metros e segundos) ----------
const GRAVITY := 22.0
const PUSH_ACCEL := 9.0
const FRICTION := 2.5
const MAX_SPEED := 15.0
const TURN_RATE := 2.6
const OLLIE_SPEED := 6.5
const TRICK_DEG_PER_SEC := 720.0
const PIVOT_Y := 0.8     # altura do centro de giro das manobras
const TRICK_NAMES := {"kick": "Kickflip", "shove": "Shove-it", "flip": "Flip"}

# ---------- Referências ----------
var skater: CharacterBody3D
var rig: Node3D           # corpo + skate; gira nas manobras
var camera: Camera3D
var hud: Label
var msg_label: Label

# ---------- Estado ----------
var yaw := 0.0
var forward_speed := 0.0
var airborne := false
var air_time := 0.0
var jump_buffer := 0.0
var trick_request := false
var trick_kind := ""
var trick_angle := 0.0
var trick_target := 0.0
var score := 0
var msg := ""
var msg_timer := 0.0

# ---------- Toque ----------
var touch_index := -1
var touch_origin := Vector2.ZERO
var touch_stick := Vector2.ZERO


func _ready() -> void:
	_build_environment()
	_build_city()
	_build_skater()
	_build_camera()
	_build_ui()
	_respawn()
	_show("Use o analógico e os botões")


# =====================================================
#  CONSTRUÇÃO DO MUNDO
# =====================================================

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.6, 0.82, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 0.7

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)


func _build_city() -> void:
	# Praça principal
	_make_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200), Color(0.45, 0.47, 0.5))

	# Faixas decorativas no chão
	for i in 8:
		_make_box(Vector3(-40 + i * 11.0, 0.01, 0), Vector3(5, 0.02, 0.4), Color(1, 1, 1))

	# Rampa (kicker) para ganhar altura
	_make_ramp(-14.0, 0.0, 6.0, 20.0, 4.0)

	# Escadas (obstáculos para dar ollie)
	for i in 3:
		_make_box(Vector3(-8, 0.15 * (i + 1), -22 - i * 1.2), Vector3(3, 0.3 * (i + 1), 1.2), Color(0.7, 0.7, 0.75))

	# Banco alto (ollie para cima)
	_make_box(Vector3(9, 0.6, -18), Vector3(6, 1.2, 3), Color(0.8, 0.4, 0.4))

	# Corrimão baixo (decoração e obstáculo)
	_make_box(Vector3(-9, 0.5, -5), Vector3(0.1, 0.1, 6), Color(0.8, 0.8, 0.85))

	# Prédios ao redor da praça
	var colors := [
		Color(0.85, 0.75, 0.55), Color(0.6, 0.7, 0.8), Color(0.9, 0.9, 0.85),
		Color(0.55, 0.6, 0.65), Color(0.8, 0.6, 0.5)
	]
	for i in 12:
		var a := TAU * i / 12.0
		var h := 12.0 + float(i % 4) * 6.0
		var pos := Vector3(cos(a) * 85.0, h / 2.0, sin(a) * 85.0)
		_make_box(pos, Vector3(12, h, 12), colors[i % colors.size()])


func _make_box(pos: Vector3, size: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg

	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	body.add_child(mi)

	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)

	add_child(body)


# Rampa que sobe em direção a -Z. near_z é onde ela começa (no chão).
func _make_ramp(near_z: float, x: float, length: float, angle: float, width: float) -> void:
	var a := deg_to_rad(angle)
	var center := Vector3(x, (length / 2.0) * sin(a) - 0.18, near_z - (length / 2.0) * cos(a))
	_make_box(center, Vector3(width, 0.4, length), Color(0.9, 0.5, 0.2), Vector3(angle, 0, 0))


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


# =====================================================
#  SKATISTA
# =====================================================

func _build_skater() -> void:
	skater = CharacterBody3D.new()
	skater.floor_snap_length = 0.3
	skater.floor_max_angle = deg_to_rad(40)

	# Colisão: cápsula de pé no chão
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	skater.add_child(cs)

	# Visual: o centro de giro fica na altura do quadril
	rig = Node3D.new()
	rig.position = Vector3(0, PIVOT_Y, 0)
	skater.add_child(rig)

	_part(rig, _box(Vector3(0.24, 0.04, 0.8)), Vector3(0, 0.07 - PIVOT_Y, 0), Color(0.95, 0.6, 0.2))
	_part(rig, _box(Vector3(0.16, 0.85, 0.16)), Vector3(-0.1, 0.55 - PIVOT_Y, 0), Color(0.2, 0.25, 0.5))
	_part(rig, _box(Vector3(0.16, 0.85, 0.16)), Vector3(0.1, 0.55 - PIVOT_Y, 0), Color(0.2, 0.25, 0.5))
	_part(rig, _box(Vector3(0.42, 0.6, 0.26)), Vector3(0, 1.08 - PIVOT_Y, 0), Color(0.9, 0.2, 0.2))
	_part(rig, _box(Vector3(0.12, 0.55, 0.12)), Vector3(-0.3, 1.05 - PIVOT_Y, 0), Color(0.9, 0.7, 0.5))
	_part(rig, _box(Vector3(0.12, 0.55, 0.12)), Vector3(0.3, 1.05 - PIVOT_Y, 0), Color(0.9, 0.7, 0.5))

	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	_part(rig, sphere, Vector3(0, 1.5 - PIVOT_Y, 0), Color(0.9, 0.7, 0.5))

	add_child(skater)


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color)
	parent.add_child(mi)


func _respawn() -> void:
	skater.position = Vector3(0, 0, 10)
	skater.velocity = Vector3.ZERO
	yaw = 0.0
	skater.rotation.y = yaw
	forward_speed = 0.0
	trick_kind = ""
	rig.rotation = Vector3.ZERO
	airborne = false
	air_time = 0.0


func _forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


# =====================================================
#  FÍSICA E MANOBRAS
# =====================================================

func _physics_process(delta: float) -> void:
	var move_in := _get_input()
	var on_floor := skater.is_on_floor()
	jump_buffer = maxf(0.0, jump_buffer - delta)

	# Direção: girar é mais fácil em velocidade e quase nulo no ar
	var steer_factor := 0.3 if not on_floor else clampf(absf(forward_speed) / 5.0, 0.15, 1.0)
	var dir_sign := 1.0 if forward_speed >= 0.0 else -1.0
	yaw -= move_in.x * TURN_RATE * steer_factor * dir_sign * delta
	skater.rotation.y = yaw

	var fwd := _forward()

	if on_floor:
		# Empurrar, frear e rolar
		if absf(move_in.y) > 0.1:
			forward_speed += move_in.y * PUSH_ACCEL * delta
		else:
			forward_speed = move_toward(forward_speed, 0.0, FRICTION * delta)
		forward_speed = clampf(forward_speed, -4.0, MAX_SPEED)

		# Segue a inclinação do chão (rampas)
		var normal := skater.get_floor_normal()
		var slope_dir := (fwd - normal * fwd.dot(normal)).normalized()
		skater.velocity = slope_dir * forward_speed - normal * 0.5

		if jump_buffer > 0.0:
			jump_buffer = 0.0
			skater.velocity.y = OLLIE_SPEED
			airborne = true
			air_time = 0.0
	else:
		# No ar: mantém a velocidade horizontal e aplica gravidade
		skater.velocity.x = fwd.x * forward_speed
		skater.velocity.z = fwd.z * forward_speed
		skater.velocity.y -= GRAVITY * delta
		air_time += delta
		if trick_request and trick_kind == "":
			_start_trick(move_in.x)

	trick_request = false

	skater.move_and_slide()

	if skater.is_on_floor():
		if airborne:
			airborne = false
			_on_land()
	else:
		airborne = true

	# Bater numa parede freia o skate
	if absf(forward_speed) > 3.0 and skater.get_real_velocity().length() < absf(forward_speed) * 0.4:
		forward_speed *= 0.6

	# Animação da manobra
	if trick_kind != "":
		trick_angle = minf(trick_angle + TRICK_DEG_PER_SEC * delta, trick_target)
		var r := deg_to_rad(trick_angle)
		match trick_kind:
			"kick":
				rig.rotation = Vector3(0, 0, r)
			"shove":
				rig.rotation = Vector3(0, r, 0)
			"flip":
				rig.rotation = Vector3(r, 0, 0)

	# Caiu do mapa
	if skater.position.y < -10.0:
		_respawn()


func _start_trick(x: float) -> void:
	# O analógico escolhe a manobra: esquerda = kickflip, direita = shove-it, centro = flip
	if x < -0.35:
		trick_kind = "kick"
	elif x > 0.35:
		trick_kind = "shove"
	else:
		trick_kind = "flip"
	trick_angle = 0.0
	trick_target = 180.0 if trick_kind == "shove" else 360.0


func _on_land() -> void:
	if trick_kind != "":
		if trick_angle >= trick_target - 1.0:
			var pts := 100 if trick_kind == "shove" else 150
			score += pts
			_show(TRICK_NAMES[trick_kind] + " +" + str(pts))
		else:
			forward_speed *= 0.4
			_show("Bail!")

	if air_time > 0.3:
		score += int(air_time * 10.0)

	trick_kind = ""
	trick_angle = 0.0
	rig.rotation = Vector3.ZERO
	air_time = 0.0


func _show(text: String) -> void:
	msg = text
	msg_timer = 1.5


# =====================================================
#  CÂMERA E INTERFACE
# =====================================================

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 70.0
	add_child(camera)
	camera.current = true
	camera.position = skater.position + Vector3(0, 3, 6)


func _process(delta: float) -> void:
	# Câmera atrás do skatista, suavizada
	var target := skater.position + _forward() * -6.5 + Vector3(0, 3.0, 0)
	camera.position = camera.position.lerp(target, 1.0 - exp(-6.0 * delta))
	camera.look_at(skater.position + Vector3(0, 1.0, 0), Vector3.UP)

	msg_timer = maxf(0.0, msg_timer - delta)
	hud.text = "Pontos: %d\nVelocidade: %.1f m/s" % [score, absf(forward_speed)]
	msg_label.text = msg if msg_timer > 0.0 else ""


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 26)
	hud.add_theme_color_override("font_color", Color.WHITE)
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	hud.add_theme_constant_override("outline_size", 6)
	root.add_child(hud)

	msg_label = Label.new()
	msg_label.anchor_left = 0.5
	msg_label.anchor_right = 0.5
	msg_label.offset_left = -220
	msg_label.offset_right = 220
	msg_label.offset_top = 90
	msg_label.offset_bottom = 140
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.add_theme_font_size_override("font_size", 34)
	msg_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	msg_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	msg_label.add_theme_constant_override("outline_size", 6)
	root.add_child(msg_label)

	jump_btn = _make_button("PULAR", root, -100, -30)
	trick_btn = _make_button("MANOBRA", root, -190, -120)
	jump_btn.button_down.connect(func(): jump_buffer = 0.15)
	trick_btn.button_down.connect(func(): trick_request = true)


func _make_button(text: String, parent: Control, offset_top: float, offset_bottom: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = -220
	b.offset_right = -40
	b.offset_top = offset_top
	b.offset_bottom = offset_bottom
	b.add_theme_font_size_override("font_size", 22)
	parent.add_child(b)
	return b


# =====================================================
#  ENTRADA
# =====================================================

# Analógico virtual: arraste na metade esquerda da tela
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if touch_index == -1 and event.position.x < get_viewport().get_visible_rect().size.x * 0.5:
				touch_index = event.index
				touch_origin = event.position
		elif event.index == touch_index:
			touch_index = -1
			touch_stick = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == touch_index:
		var d: Vector2 = (event.position - touch_origin) / 90.0
		d.y = -d.y
		touch_stick = d.limit_length(1.0)


# Teclado para testar no computador
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			jump_buffer = 0.15
		elif event.keycode == KEY_Z or event.keycode == KEY_X:
			trick_request = true


func _get_input() -> Vector2:
	if touch_stick.length() > 0.05:
		return touch_stick
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y -= 1.0
	return v.limit_length(1.0)

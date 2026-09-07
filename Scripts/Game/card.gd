class_name Card3D
extends Node3D

# ── Estado ──────────────────────────────────────────────────────────────────
enum CardState { IN_DECK, IN_HAND, ON_TABLE, DRAGGING }
var current_state: CardState = CardState.IN_DECK
var previous_state: CardState

# ── Datos ────────────────────────────────────────────────────────────────────
var card_id: int = -1        # ID único para sincronización multijugador
var value: int
var suit: String
var is_face_up: bool = false
var owner_id: int = -1       # peer_id del jugador dueño de la carta
@export var min_distance: float = 0.4

# ── Drag ─────────────────────────────────────────────────────────────────────
static var any_card_dragging: bool = false
var is_dragging: bool = false
var is_press_pending: bool = false
var drag_plane: Plane          # Plano 3D contra el que proyectamos el mouse
var drag_offset: Vector3
var start_drag_pos: Vector3
var press_start_mouse_pos: Vector2

const DRAG_THRESHOLD: float = 8.0
const DRAG_HEIGHT: float = 0.3  # Altura a la que flota la carta al arrastrar

# ── Referencias ──────────────────────────────────────────────────────────────
@onready var front: MeshInstance3D = $Front
@onready var back: MeshInstance3D  = $Back

# ── Inicialización ───────────────────────────────────────────────────────────
func initialize(v: int, s: String, id: int) -> void:
	value  = v
	suit   = s
	card_id = id

	var front_path = "res://Assets/Cards/Fronts/" + suit.to_lower() + "_" + str(value) + ".png"
	var back_path  = "res://Assets/Cards/Backs/card_back.png"

	if ResourceLoader.exists(front_path):
		var mat = StandardMaterial3D.new()
		mat.albedo_texture = load(front_path)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		front.material_override = mat
	else:
		push_error("Card: no se encontró la imagen -> " + front_path)

	var back_mat = StandardMaterial3D.new()
	back_mat.albedo_texture = load(back_path)
	back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back.material_override = back_mat

	update_visuals()

func change_state(new_state: CardState) -> void:
	current_state = new_state

func flip() -> void:
	is_face_up = !is_face_up
	update_visuals()

func update_visuals() -> void:
	front.visible = is_face_up
	back.visible  = !is_face_up

# ── Input ────────────────────────────────────────────────────────────────────
func handle_input_event(camera: Camera3D, event: InputEvent) -> void:
	var is_click = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
	var is_touch = event is InputEventScreenTouch

	if (is_click or is_touch) and event.pressed:
		if current_state == CardState.DRAGGING:
			return
		get_viewport().set_input_as_handled()
		_handle_touch_down(camera, event.position)

func _handle_touch_down(_camera: Camera3D, mouse_pos: Vector2) -> void:
	if any_card_dragging:
		return
	previous_state = current_state

	match current_state:
		CardState.IN_HAND:
			start_drag_pos      = global_position
			press_start_mouse_pos = mouse_pos
			is_press_pending    = true

		CardState.ON_TABLE:
			start_drag_pos      = global_position
			press_start_mouse_pos = mouse_pos
			is_press_pending    = true

		CardState.IN_DECK:
			start_drag_pos      = global_position
			press_start_mouse_pos = mouse_pos
			is_press_pending    = true

func _start_drag(camera: Camera3D) -> void:
	any_card_dragging = true
	is_dragging       = true
	change_state(CardState.DRAGGING)

	# Siempre arrastramos a altura fija sobre la mesa, sin importar de dónde viene la carta
	drag_plane = Plane(Vector3.UP, DRAG_HEIGHT)
	
	var origin    = camera.project_ray_origin(press_start_mouse_pos)
	var direction = camera.project_ray_normal(press_start_mouse_pos)
	var hit       = drag_plane.intersects_ray(origin, direction)
	if hit:
		drag_offset = start_drag_pos - hit
		drag_offset.y = 0.0  # ignoramos offset vertical

	match previous_state:
		CardState.IN_HAND:
			# Se levanta un poco al salir de la mano
			position.y += 0.1

func _input(event: InputEvent) -> void:
	if is_dragging or is_press_pending:
		var is_click_release = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
		var is_touch_release = event is InputEventScreenTouch and not event.pressed

		if is_click_release or is_touch_release:
			_handle_touch_up()

func _handle_touch_up() -> void:
	is_dragging       = false
	is_press_pending  = false
	any_card_dragging = false

	var hand_zone = _get_overlap_zone("hand_zone")
	var deck_zone = _get_overlap_zone("deck_area") # Busca cualquier mazo/pila

	# 1. ¿Soltamos sobre un Mazo/Pila?
	if deck_zone:
		var deck = deck_zone.get_parent()
		if deck is Deck3D:
			# Si vino de la mano, la sacamos lógicamente primero
			if previous_state == CardState.IN_HAND:
				var hand = get_parent()
				if hand is Hand3D:
					hand.remove_card(self)
					
			_sync_drop_on_deck(deck)
			return

	# 2. ¿Soltamos sobre la Mano?
	if hand_zone:
		var hand = get_tree().get_first_node_in_group("hand_group")
		if hand:
			if previous_state == CardState.ON_TABLE:
				hand.add_card(self)
			elif previous_state == CardState.IN_HAND:
				change_state(CardState.IN_HAND)
				hand.reposition_cards()
			elif previous_state == CardState.IN_DECK:
				hand.add_card(self)
			return

	# 3. ¿Chocamos con otra carta suelta en la mesa para armar una pila nueva?
	if previous_state == CardState.IN_HAND or previous_state == CardState.IN_DECK or previous_state == CardState.ON_TABLE:
		if _check_merge_with_other_card():
			# Si venía de la mano, la borramos de la lógica del abanico
			if previous_state == CardState.IN_HAND:
				var hand = get_parent()
				if hand is Hand3D:
					hand.remove_card(self)
			return # Terminamos aquí, ya se creó la pila
			
	# 4. Si no chocó con nada, cae libre en la mesa
	if previous_state == CardState.IN_HAND:
		_request_drop_on_table()
		
	elif previous_state == CardState.IN_DECK or previous_state == CardState.ON_TABLE:
		change_state(CardState.ON_TABLE)
		if previous_state == CardState.ON_TABLE and global_position.distance_to(start_drag_pos) < 0.05:
			flip()
		global_position.y = 0.05

# ── Detección de zona por raycast ────────────────────────────────────────────
func _get_overlap_zone(group: String) -> CollisionObject3D:
	var zones = get_tree().get_nodes_in_group(group)
	for zone in zones:
		if zone is CollisionObject3D:
			var local_pos = zone.to_local(global_position)
			var shape_node = zone.get_child(0) as CollisionShape3D
			if shape_node and shape_node.shape is BoxShape3D:
				var half = (shape_node.shape as BoxShape3D).size / 2.0
				var offset = shape_node.position
				var rel = local_pos - offset
				if abs(rel.x) <= half.x and abs(rel.y) <= half.y + 1.0 and abs(rel.z) <= half.z:
					return zone
	return null

# ── Acción multijugador-friendly ─────────────────────────────────────────────
func _request_drop_on_table() -> void:
	# Por ahora ejecuta local; cuando agreguemos red será un RPC
	_sync_drop_on_table(global_position)

func _sync_drop_on_table(pos: Vector3) -> void:
	change_state(CardState.ON_TABLE)
	var hand = get_parent()
	if hand is Hand3D:
		hand.drop_card_on_table(self)
	global_position = pos
	position.y      = 0.0

# ── Process ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if is_press_pending:
		var mouse_now = get_viewport().get_mouse_position()
		if mouse_now.distance_to(press_start_mouse_pos) > DRAG_THRESHOLD:
			is_press_pending = false
			var camera = get_viewport().get_camera_3d()
			if camera:
				_start_drag(camera)

	if is_dragging:
		var camera = get_viewport().get_camera_3d()
		if camera:
			var origin    = camera.project_ray_origin(get_viewport().get_mouse_position())
			var direction = camera.project_ray_normal(get_viewport().get_mouse_position())
			var hit       = drag_plane.intersects_ray(origin, direction)
			if hit:
				global_position = hit + drag_offset
				global_position.y = drag_plane.d  # Mantiene altura fija al arrastrar

		# Suaviza la rotación a 0 mientras se arrastra
		rotation.z = lerp_angle(rotation.z, 0.0, clamp(10.0 * delta, 0.0, 1.0))

func _sync_drop_on_deck(deck: Deck3D) -> void:
	# Aquí en el futuro llamaremos a los RPC para el multijugador
	deck.receive_card(self)

func _check_merge_with_other_card() -> bool:
	var table = null
	# Buscamos la mesa (si está en la mano, la mesa es el abuelo; si está suelta, es el padre)
	if get_parent() is Table3D:
		table = get_parent()
	elif get_parent() and get_parent().get_parent() is Table3D:
		table = get_parent().get_parent()
		
	if not table: 
		return false
		
	# Buscamos todas las cartas en la mesa
	for sibling in table.get_children():
		if sibling is Card3D and sibling != self and sibling.current_state == CardState.ON_TABLE:
			# Medimos la distancia plana (X y Z, ignorando la altura Y)
			var dist = Vector2(global_position.x, global_position.z).distance_to(Vector2(sibling.global_position.x, sibling.global_position.z))
			if dist < min_distance: # Si están cerca, las fusionamos
				table.create_new_pile(self, sibling)
				return true
	return false

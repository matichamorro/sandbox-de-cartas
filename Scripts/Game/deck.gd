class_name Deck3D
extends Node3D

@export var card_scene: PackedScene
@export var is_main_deck: bool = true # True para el mazo inicial, False para pilas creadas en el juego

var suits: Array[String] = ["Gold", "Cup", "Sword", "Club"]
var cards_in_deck: Array[Card3D] = []
var _next_card_id: int = 0

# ── Referencias ──────────────────────────────────────────────────────────────
# Usamos get_node_or_null para que no crashee si los nodos tienen otro nombre temporalmente
@onready var base_mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
@onready var top_card_mesh: MeshInstance3D = get_node_or_null("TopCardMesh")
@onready var count_label: Label3D = get_node_or_null("CountLabel")

# ── Variables de Arrastre (Drag) ─────────────────────────────────────────────
var is_press_pending: bool = false
var is_dragging_deck: bool = false
var press_start_mouse_pos: Vector2
var press_time: float = 0.0
var drag_plane: Plane
var drag_offset: Vector3

const DRAG_THRESHOLD: float = 8.0
const LONG_PRESS_TIME: float = 0.15   # Tiempo para "agarrar" todo el mazo
const DRAG_HEIGHT: float = 0.2        # Altura de vuelo del mazo
const CARD_THICKNESS: float = 0.005   # Cuánto engorda la caja por cada carta

func _ready() -> void:
	if is_main_deck:
		build_deck()
		shuffle_deck()
	_update_visuals()

func build_deck() -> void:
	# Generamos la baraja española
	for suit in suits:
		for value in range(1, 13):
			var new_card = card_scene.instantiate() as Card3D
			add_child(new_card)
			new_card.initialize(value, suit, _next_card_id)
			_next_card_id += 1
			new_card.change_state(Card3D.CardState.IN_DECK)
			new_card.visible = false
			cards_in_deck.append(new_card)

func shuffle_deck() -> void:
	cards_in_deck.shuffle()

func peek_top_card() -> Card3D:
	if cards_in_deck.is_empty():
		return null
	return cards_in_deck.back()

func remove_card(card: Card3D) -> void:
	cards_in_deck.erase(card)
	_update_visuals()

# ── Formar Pilas (Recibir cartas) ─────────────────────────────────────────────
func receive_card(card: Card3D) -> void:
	card.change_state(Card3D.CardState.IN_DECK)
	if card.get_parent() != self:
		card.reparent(self)
	
	card.visible = false
	card.position = Vector3.ZERO
	cards_in_deck.append(card)
	
	_update_visuals()

# ── Magia Visual (Volumen + Textura Dinámica) ────────────────────────────────
func _update_visuals() -> void:
	if cards_in_deck.is_empty():
		visible = false
		# Si es una pila de la mesa que se quedó sin cartas, la destruimos
		if not is_main_deck:
			queue_free() 
		return
		
	visible = true
	var top_card = cards_in_deck.back()
	
	# Calculamos el grosor del mazo
	var deck_height = max(0.01, cards_in_deck.size() * CARD_THICKNESS)
	
	# 1. Ajustar el volumen de la caja (BoxMesh) con checkeo de seguridad
	if base_mesh:
		base_mesh.scale.y = deck_height
		base_mesh.position.y = deck_height / 2.0 # Crece hacia arriba
	else:
		push_warning("Deck3D: Falta el nodo 'MeshInstance3D' en la escena.")
	
	# 2. Posicionar la tapa y copiar textura
	if top_card_mesh:
		top_card_mesh.position.y = deck_height + 0.001
		
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		
		if top_card.is_face_up:
			if top_card.front and top_card.front.material_override:
				mat.albedo_texture = top_card.front.material_override.albedo_texture
		else:
			if top_card.back and top_card.back.material_override:
				mat.albedo_texture = top_card.back.material_override.albedo_texture
			
		top_card_mesh.material_override = mat
	else:
		push_warning("Deck3D: Falta el nodo 'TopCardMesh' en la escena.")
		
	# Agrego el contador por encima de deck_height
	if count_label:
		if cards_in_deck.size() >= 2:
			count_label.text = str(cards_in_deck.size())
			count_label.visible = true
			count_label.position.y = deck_height + 0.3
			count_label.no_depth_test = true
		else:
			count_label.visible = false
	else:
		push_warning("Deck3D: Falta el nodo 'CountLabel' en la escena.")

# ── Input (Robar vs Mover Mazo) ───────────────────────────────────────────────
func on_deck_pressed(camera: Camera3D, mouse_pos: Vector2) -> void:
	if Card3D.any_card_dragging or is_dragging_deck:
		return
	is_press_pending = true
	press_time = 0.0
	press_start_mouse_pos = mouse_pos

func _process(delta: float) -> void:
	if is_press_pending:
		press_time += delta
		var mouse_now = get_viewport().get_mouse_position()
		var dist = mouse_now.distance_to(press_start_mouse_pos)

		if dist > DRAG_THRESHOLD:
			is_press_pending = false
			# LÓGICA CLAVE: Moviste rápido = Robar ; Mantuviste presionado = Arrastrar Mazo
			if press_time < LONG_PRESS_TIME:
				_peel_top_card(mouse_now) 
			else:
				_start_dragging_deck()
				
		elif press_time >= LONG_PRESS_TIME:
			# Feedback: El mazo "salta" a tu mano para avisar que lo agarraste
			global_position.y = lerp(global_position.y, DRAG_HEIGHT, 15.0 * delta)

	if is_dragging_deck:
		var camera = get_viewport().get_camera_3d()
		if camera:
			var origin = camera.project_ray_origin(get_viewport().get_mouse_position())
			var dir = camera.project_ray_normal(get_viewport().get_mouse_position())
			var hit = drag_plane.intersects_ray(origin, dir)
			if hit:
				global_position = hit + drag_offset
				global_position.y = drag_plane.d # Lo mantiene a altura de vuelo

func _input(event: InputEvent) -> void:
	if is_press_pending or is_dragging_deck:
		var is_click_release = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
		var is_touch_release = event is InputEventScreenTouch and not event.pressed

		if is_click_release or is_touch_release:
			is_press_pending = false
			if is_dragging_deck:
				is_dragging_deck = false
				_handle_deck_drop()
			else:
				# Toque corto sin mover (Podemos usarlo a futuro para Voltear el mazo)
				global_position.y = 0.01

func _start_dragging_deck() -> void:
	is_dragging_deck = true
	drag_plane = Plane(Vector3.UP, DRAG_HEIGHT)
	var camera = get_viewport().get_camera_3d()
	var origin = camera.project_ray_origin(press_start_mouse_pos)
	var dir = camera.project_ray_normal(press_start_mouse_pos)
	var hit = drag_plane.intersects_ray(origin, dir)
	if hit:
		drag_offset = global_position - hit
		drag_offset.y = 0

func _handle_deck_drop() -> void:
	var target_zone = _get_overlap_zone("deck_area")

	if target_zone:
		var target_deck = target_zone.get_parent()
		if target_deck is Deck3D and target_deck != self:
			var table = get_parent()
			if table is Table3D:
				table.merge_decks(self, target_deck)
				return # No hace falta reposicionarnos, la pila se va a fusionar y destruir

	# Si no cayó sobre otra pila, la apoyamos normalmente en la mesa
	global_position.y = 0.01

func _get_overlap_zone(group: String) -> CollisionObject3D:
	var zones = get_tree().get_nodes_in_group(group)
	for zone in zones:
		if zone is CollisionObject3D:
			if zone.get_parent() == self:
				continue # Ignoramos nuestra propia área de colisión
			var local_pos = zone.to_local(global_position)
			var shape_node = zone.get_child(0) as CollisionShape3D
			if shape_node and shape_node.shape is BoxShape3D:
				var half = (shape_node.shape as BoxShape3D).size / 2.0
				var offset = shape_node.position
				var rel = local_pos - offset
				if abs(rel.x) <= half.x and abs(rel.y) <= half.y + 1.0 and abs(rel.z) <= half.z:
					return zone
	return null


func _peel_top_card(mouse_pos: Vector2) -> void:
	var top_card = peek_top_card()
	if top_card == null:
		return
		
	remove_card(top_card)
	top_card.visible = true
	top_card.global_position = global_position
	top_card.global_position.y = 0.05
	
	var table = get_parent()
	if table:
		top_card.reparent(table)

	# Forzamos a la carta a entrar en estado de Dragging directamente
	top_card.previous_state = Card3D.CardState.IN_DECK
	top_card.start_drag_pos = top_card.global_position
	top_card.press_start_mouse_pos = mouse_pos
	top_card.is_press_pending = true

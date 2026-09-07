class_name Table3D
extends Node3D

@onready var camera: Camera3D              = $Camera3D
@onready var deck: Deck3D                  = $Deck3D
@onready var hand: Hand3D                  = $Hand3D
@onready var minimap_camera: Camera3D      = $MinimapViewport/MinimapCamera
@onready var minimap_button: TextureButton = $CanvasLayer/MinimapButton

# Cargamos la escena una sola vez al inicio en la memoria
@onready var deck_scene: PackedScene       = preload("res://Scenes/Game/Deck.tscn")

var _is_handling_press: bool = false
var _is_top_view: bool = false
var _original_camera_transform: Transform3D
var _original_fov: float

func _ready() -> void:
	_original_camera_transform = camera.global_transform
	_original_fov              = camera.fov
	minimap_button.pressed.connect(_on_minimap_pressed)

func _on_minimap_pressed() -> void:
	_is_top_view = !_is_top_view

	# Guardamos los datos actuales de "camera"
	var temp_transform: Transform3D = camera.global_transform
	var temp_projection: int = camera.projection
	var temp_fov: float = camera.fov
	var temp_size: float = camera.size

	# "camera" toma los datos de "minimap_camera"
	camera.global_transform = minimap_camera.global_transform
	camera.projection       = minimap_camera.projection
	camera.fov              = minimap_camera.fov
	camera.size             = minimap_camera.size

	# "minimap_camera" toma los datos que tenía "camera" antes
	minimap_camera.global_transform = temp_transform
	minimap_camera.projection       = temp_projection
	minimap_camera.fov              = temp_fov
	minimap_camera.size             = temp_size

func _input(event: InputEvent) -> void:
	var is_click = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
	var is_touch = event is InputEventScreenTouch

	if (is_click or is_touch) and event.pressed:
		if _is_handling_press:
			return
		_is_handling_press = true
		_handle_press(event.position)
		call_deferred("_reset_press_guard")

func _reset_press_guard() -> void:
	_is_handling_press = false

func _handle_press(mouse_pos: Vector2) -> void:
	if Card3D.any_card_dragging:
		return

	var result = _raycast_from_mouse(mouse_pos)
	if result.is_empty():
		return

	var collider = result["collider"]

	if collider.is_in_group("deck_area"):
		var clicked_deck = _get_deck_from_collider(collider)
		if clicked_deck:
			clicked_deck.on_deck_pressed(camera, mouse_pos)
		return

	var card = _get_card_from_collider(collider)
	if card:
		card.handle_input_event(camera, _make_input_event(mouse_pos))

func _raycast_from_mouse(mouse_pos: Vector2) -> Dictionary:
	var origin    = camera.project_ray_origin(mouse_pos)
	var direction = camera.project_ray_normal(mouse_pos)
	var end       = origin + direction * 100.0

	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = 0xFFFFFFFF

	return space.intersect_ray(query)

func _get_card_from_collider(collider: Object) -> Card3D:
	var node = collider
	while node:
		if node is Card3D:
			return node
		node = node.get_parent()
	return null

func _get_deck_from_collider(collider: Object) -> Deck3D:
	var node = collider
	while node:
		if node is Deck3D:
			return node
		node = node.get_parent()
	return null

func _make_input_event(mouse_pos: Vector2) -> InputEventMouseButton:
	var event          = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed      = true
	event.position     = mouse_pos
	return event

# --- FUNCIONES DIFERIDAS POR SEGURIDAD DE FÍSICAS ---

func create_new_pile(top_card: Card3D, bottom_card: Card3D) -> void:
	# Diferimos la creación para no romper las físicas
	call_deferred("_perform_create_new_pile", top_card, bottom_card)

func _perform_create_new_pile(top_card: Card3D, bottom_card: Card3D) -> void:
	if deck_scene:
		print("Mesa: Creando nueva pila de 2 cartas.")
		var new_pile = deck_scene.instantiate() as Deck3D
		new_pile.is_main_deck = false 
		
		new_pile.cards_in_deck.append(bottom_card)
		add_child(new_pile)
		new_pile.cards_in_deck.clear()
		
		new_pile.global_position = bottom_card.global_position
		new_pile.global_position.y = 0.01
		
		new_pile.receive_card(bottom_card)
		new_pile.receive_card(top_card)

func merge_decks(dragged_deck: Deck3D, target_deck: Deck3D) -> void:
	print("Mesa: Solicitud de fusión. Diferimos la ejecución por seguridad.")
	call_deferred("_perform_merge", dragged_deck, target_deck)

func _perform_merge(dragged_deck: Deck3D, target_deck: Deck3D) -> void:
	# Validamos que ambos mazos sigan existiendo antes de operar
	if not is_instance_valid(dragged_deck) or not is_instance_valid(target_deck):
		return

	print("Mesa: Fusionando mazos... Pasando cartas al mazo destino.")
	
	# Duplicamos la lista de cartas para iterar seguros
	var cards_to_move = dragged_deck.cards_in_deck.duplicate()
	dragged_deck.cards_in_deck.clear()
	
	# Pasamos todas las cartas del mazo que soltaste al mazo destino
	for card in cards_to_move:
		target_deck.receive_card(card)
	
	# Destruimos el mazo que arrastramos porque ahora quedó vacío de manera segura
	dragged_deck.queue_free()
	print("Mesa: Fusión completada. El mazo ahora tiene ", target_deck.cards_in_deck.size(), " cartas.")

class_name Hand3D
extends Node3D

@export var card_spacing: float = 0.4      # Separación entre cartas en X
@export var max_angle_spread: float = 30.0 # Rotación total del abanico en Y (grados)
@export var hand_tilt: float = 25.0        # Inclinación de las cartas hacia el jugador (grados en X)
@export var is_visible_to_others: bool = false
@export var player_id: int = -1

var cards_in_hand: Array[Card3D] = []

func add_card(new_card: Card3D) -> void:
	new_card.change_state(Card3D.CardState.IN_HAND)
	new_card.owner_id = player_id

	if new_card.get_parent() != self:
		new_card.reparent(self)

	new_card.visible = true

	if not new_card.is_face_up:
		new_card.flip()

	cards_in_hand.append(new_card)
	reposition_cards()

func reposition_cards() -> void:
	var card_count = cards_in_hand.size()
	if card_count == 0:
		return

	if card_count == 1:
		cards_in_hand[0].position = Vector3.ZERO
		cards_in_hand[0].rotation = Vector3(deg_to_rad(-hand_tilt), 0.0, 0.0)
		return

	# Distribuimos las cartas linealmente en X centradas en el origen
	var total_width  = card_spacing * (card_count - 1)
	var start_x      = -total_width / 2.0

	# Rotación en Y: la carta más a la izquierda rota positivo, la derecha negativo
	var angle_per_card = max_angle_spread / (card_count - 1)
	var start_angle    = max_angle_spread / 2.0

	for i in range(card_count):
		var card      = cards_in_hand[i]
		var x_pos     = start_x + i * card_spacing
		var angle_y   = deg_to_rad(start_angle - i * angle_per_card)

		card.position = Vector3(x_pos, 0.001 * i, 0.0)
		card.rotation = Vector3(deg_to_rad(-hand_tilt), angle_y, 0.0)

func drop_card_on_table(card: Card3D) -> void:
	cards_in_hand.erase(card)
	reposition_cards()
	call_deferred("_finalize_drop", card)

func _finalize_drop(card: Card3D) -> void:
	var table = get_parent()
	card.reparent(table)
	card.rotation    = Vector3.ZERO
	card.is_dragging = false
	card.change_state(Card3D.CardState.ON_TABLE)
	card.position.y  = 0.05

func remove_card(card: Card3D) -> void:
	cards_in_hand.erase(card)
	reposition_cards()

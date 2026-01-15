extends Control

func _ready() -> void:
	# Hide card system UI as requested for transition
	var parent = get_parent()
	if parent:
		var hand = parent.get_node_or_null("Hand")
		if hand: hand.visible = false
		
		var deck_pile = parent.get_node_or_null("DeckPileButton")
		if deck_pile: deck_pile.visible = false
		
		var play_hand = parent.get_node_or_null("PlayHandButton")
		if play_hand: play_hand.visible = false
		
		var disposal = parent.get_node_or_null("DisposalZone")
		if disposal: disposal.visible = false
		
		var play_area = parent.get_node_or_null("PlayArea")
		if play_area: play_area.visible = false

extends CanvasLayer
var inventory: KartInventory
@onready var name_label: Label = $Panel/Rows/ItemName
@onready var description: Label = $Panel/Rows/Description

func _process(_delta: float) -> void:
	if inventory == null:
		return
	var item: ItemDefinition = inventory.held
	name_label.text = "EMPTY" if item == null else item.display_name
	name_label.modulate = Color("9aacba") if item == null else item.color
	description.text = "Drive through a cyan item box" if item == null else item.description
	if inventory.kart.controls.suppression_remaining > 0.0:
		description.text = "SPIN OUT · %.1f s" % inventory.kart.controls.suppression_remaining

class_name CustomizationLibrary
extends Resource
@export var kart: PartsRegistry
@export var character: PartsRegistry
const LEGACY_FIELDS: Dictionary = {&"body_type_id":&"body_id",&"hair_id":&"hair_id",&"eye_id":&"eyes_id",&"shirt_id":&"shirt_id",&"pants_id":&"pants_id",&"shoe_id":&"shoes_id",&"skin_tone_id":&"skin_tone_id"}

func slot(field: StringName) -> CustomizationSlot:
	var found: CustomizationSlot = kart.slot(field)
	return found if found != null else character.slot(field)

func part(field: StringName, id: int) -> CustomizationPart:
	var category: CustomizationSlot = slot(field)
	return category.entry(id) if category != null else null

func accepts(profile: CustomizationProfile) -> bool:
	if profile == null:
		return false
	for field: StringName in CustomizationProfile.FIELDS:
		if part(field,int(profile.get(field))) == null:
			return false
	return true

func tint(profile: CustomizationProfile, field: StringName) -> Color:
	return part(field,int(profile.get(field))).color

func make_material(definition: CustomizationPart, profile: CustomizationProfile) -> ShaderMaterial:
	if definition.material == null:
		return null
	var material := definition.material.duplicate() as ShaderMaterial
	if not definition.tint_source.is_empty():
		material.set_shader_parameter(definition.tint_uniform,tint(profile,definition.tint_source))
	return material

func from_legacy(look: CharacterLook) -> CustomizationProfile:
	var result := CustomizationProfile.new()
	for field: StringName in LEGACY_FIELDS:
		var id: int = slot(field).legacy_id(look.get(LEGACY_FIELDS[field]))
		if id >= 0:
			result.set(field,id)
	return result

func legacy_look(profile: CustomizationProfile) -> CharacterLook:
	var result := CharacterLook.new()
	for field: StringName in LEGACY_FIELDS:
		result.set(LEGACY_FIELDS[field],part(field,int(profile.get(field))).legacy_key)
	return result

extends "res://tools/phase_7/verify_audio.gd"
## Reuse the full Phase 7 suite with a separate customization save as well as its audio save.
func _enter_tree() -> void:
	GameSession.profile_store.path = "res://artifacts/phase8b/offline-profile.json"
	GameSession.reload_profile()
	super()

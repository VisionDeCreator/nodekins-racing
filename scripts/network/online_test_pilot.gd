extends KartAI
## QA only: steers the client's real predicted kart; it sends ordinary input commands.
func _physics_process(delta: float) -> void:
	var state: Dictionary = RaceManager.get_racer_state(racer_id)
	if state.is_empty() or RaceManager.phase != RaceManager.Phase.RACING or state.finished or state.respawning:
		kart.controls.set_command(0,1,0,false)
		return
	# Guide from the local pose, never edit the server-owned checkpoint/lap read model.
	var best: Dictionary = {"offset":INF}
	for gate in range(RaceManager.route.checkpoint_indices.size()):
		var candidate: Dictionary = RaceManager.route.project_sector(kart.global_position,gate)
		if candidate.offset < best.offset:
			best = candidate
	state.lap_distance = best.distance
	_drive(delta,state)
	var inv: KartInventory = kart.get_node("Inventory")
	if inv.held != null and inv.held.effect.cpu_should_use(inv,inv.held):
		kart.controls.request_item_use()

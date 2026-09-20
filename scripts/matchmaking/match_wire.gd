extends Node
## Separate RPC namespace/MultiplayerAPI from the race transport. Clients submit no track.
@rpc("any_peer","call_remote","reliable")
func find_match(request_id: int, profile: PackedByteArray) -> void:
	get_parent().queue_request(multiplayer.get_remote_sender_id(),request_id,profile)

@rpc("any_peer","call_remote","reliable")
func cancel_match(request_id: int) -> void:
	get_parent().queue_cancel(multiplayer.get_remote_sender_id(),request_id)

@rpc("authority","call_remote","reliable")
func update_status(request_id: int, state: String, message: String, data: Dictionary) -> void:
	get_parent().receive_status(request_id,state,message,data)

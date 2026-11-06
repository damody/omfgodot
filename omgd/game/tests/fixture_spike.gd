# P0 S1: connect to omoba-renderer-fixture and print what arrives.
# godot --headless --path omgd/game --script res://tests/fixture_spike.gd -- ADDRESS PLAYER TEAM
extends SceneTree

const TIMEOUT_MS := 15000

var session: OmSession
var deadline := 0
var frames := 0
var last_state := -2


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	session = OmSession.new()
	print("om_bridge abi=", OmSession.abi_version())
	if not session.start(args[0], int(args[1]), int(args[2])):
		printerr("start failed: ", session.last_error())
		quit(2)
		return
	deadline = Time.get_ticks_msec() + TIMEOUT_MS


func _process(_delta: float) -> bool:
	var state := session.session_state()
	if state != last_state:
		print("session_state=", state)
		last_state = state
	if session.poll_frame():
		var ids := session.unit_ids()
		if ids.size() > 0:
			frames += 1
			var row := session.unit_rows()
			print("tick=", session.tick(), " units=", ids.size(), " first=", ids[0],
				" pos=(", row[0], ",", row[1], ") hp=", row[3], "/", row[4], " kind=", row[5])
			# The fixture publishes one snapshot and then waits for control input.
			if frames >= 1:
				print("SPIKE_OK")
				session.stop()
				quit(0)
				return true
	if Time.get_ticks_msec() > deadline:
		printerr("timeout; err=", session.last_error())
		session.stop()
		quit(1)
		return true
	return false

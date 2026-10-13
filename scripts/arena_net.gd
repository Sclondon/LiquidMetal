extends Node
## The arena's connection to the battle room on the Scareathon server (/liquid-metal/ws; see
## server/liquidMetal/arena.js in scareathon-v3). Everyone who opens the arena drops into the
## same room. The server keeps what all the games have to agree on (who's in, each runner's mass,
## the drops on the floor, who burst whom, the round clock); each game moves its own runner.
##
## Text messages are JSON, both ways:
##   to the server:  join {name}  ·  take {e, d} (runner e ran over drop d)  ·  hit {a, v, how}
##     (my runner a burst runner v)  ·  died {e} (hit a wall)  ·  spawn {e} (back on its feet)
##   from it:  welcome {you, half, blocks, drops, ents, phase, ends}  ·  ent {...} / gone {id}
##     (someone in, out)  ·  bots {ids} (the bots this game runs)  ·  took {e, d, m}  ·
##     drops {list}  ·  kill {a, v, am, how, lost, drops}  ·  alive {e, m}  ·  over {top, next}  ·
##     round {ends, drops, ents}
## Binary packets are runner states (player.gd's net_state: 11 bytes each after a kind byte),
## passed on by the server to everyone else as they are.

signal message(m: Dictionary)
signal states(data: PackedByteArray)
signal failed # couldn't get in, or the connection dropped

const PATH := "/liquid-metal/ws"
const K_STATE := 1
const GIVE_UP := 6.0 # seconds to wait to be let in

var online := true
var _ws: WebSocketPeer
var _name := ""
var _waiting := 0.0
var _welcomed := false
var _joined := false


func open(player_name: String, server: String) -> void:
	_name = player_name
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 18
	var url := server.trim_suffix("/").replace("https://", "wss://").replace("http://", "ws://") + PATH
	if _ws.connect_to_url(url) != OK:
		_fail.call_deferred()


func close() -> void:
	if _ws:
		_ws.close()
	_ws = null


func send(m: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(m))


func send_states(data: PackedByteArray) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN and _welcomed:
		_ws.send(data, WebSocketPeer.WRITE_MODE_BINARY)


func _fail() -> void:
	if _ws == null:
		return
	close()
	failed.emit()


func _process(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _joined:
				_joined = true
				send({ t = "join", name = _name })
			while _ws and _ws.get_available_packet_count() > 0:
				var data := _ws.get_packet()
				if not _ws.was_string_packet():
					if data.size() > 1 and data[0] == K_STATE:
						states.emit(data)
					continue
				var m: Variant = JSON.parse_string(data.get_string_from_utf8())
				if m is Dictionary:
					if m.get("t") == "welcome":
						_welcomed = true
					elif m.get("t") == "full":
						_fail()
						return
					message.emit(m)
		WebSocketPeer.STATE_CLOSED:
			_fail()
			return
	if not _welcomed:
		_waiting += delta
		if _waiting > GIVE_UP:
			_fail()

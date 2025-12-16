extends Node
class_name NetworkReceiver

signal tracking_updated(state: TrackingState)
signal connection_state_changed(running: bool)

@export var listen_ip := "0.0.0.0"
@export var listen_port := 11573
@export var auto_start := true
@export var expected_face_id := 0

const BINARY_HEADER_BYTES := 8 + 4 + 4 + 4 + 8 + 1 + 4 + 4 * 4 + 3 * 4 + 3 * 4
const BINARY_LANDMARKS := 70

var _udp := PacketPeerUDP.new()
var _running := false
var _last_packet_time := 0.0
var _packet_counter := 0
var _packet_timer := 0.0
var _current_rate := 0.0

func _ready() -> void:
	if auto_start:
		start()

func start(ip := "", port := -1) -> void:
	if ip != "":
		listen_ip = ip
	if port > 0:
		listen_port = port
	stop()
	var err := _udp.bind(listen_port, listen_ip)
	if err != OK:
		push_warning("Could not bind UDP socket: %s" % error_string(err))
		_last_packet_time = -INF
		return
	_udp.set_dest_address(listen_ip, listen_port)
	_udp.set_broadcast_enabled(true)
	_running = true
	_last_packet_time = -INF
	emit_signal("connection_state_changed", true)

func stop() -> void:
	if _running:
		_udp.close()
		_running = false
		emit_signal("connection_state_changed", false)
	_last_packet_time = -INF

func _process(delta: float) -> void:
	if not _running:
		return
	_packet_timer += delta
	while _udp.get_available_packet_count() > 0:
		var arr: PackedByteArray = _udp.get_packet()
		_packet_counter += 1
		_last_packet_time = Time.get_unix_time_from_system()
		var parsed_state := _parse_packet(arr)
		if parsed_state:
			parsed_state.packet_rate = _current_rate
			emit_signal("tracking_updated", parsed_state)
	if _packet_timer >= 1.0:
		_current_rate = float(_packet_counter) / _packet_timer
		_packet_counter = 0
		_packet_timer = 0.0

func _parse_packet(packet: PackedByteArray) -> TrackingState:
	if packet.is_empty():
		return null
	var text := packet.get_string_from_utf8()
	var data = JSON.parse_string(text)
	if typeof(data) == TYPE_DICTIONARY:
		return _parse_json(data)
	return _parse_binary(packet)

func _parse_binary(packet: PackedByteArray) -> TrackingState:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.data_array = packet
	if buffer.get_available_bytes() < BINARY_HEADER_BYTES:
		return null
	var timestamp := buffer.get_double()
	var face_id := buffer.get_32()
	var _frame_width := buffer.get_float()
	var _frame_height := buffer.get_float()
	var blink_left := buffer.get_float()
	var blink_right := buffer.get_float()
	var success := buffer.get_u8() == 1
	var pnp_error := buffer.get_float()
	# Quaternion (unused, but consume to align with the stream)
	buffer.get_float()
	buffer.get_float()
	buffer.get_float()
	buffer.get_float()
	var euler := [buffer.get_float(), buffer.get_float(), buffer.get_float()]
	var translation := [buffer.get_float(), buffer.get_float(), buffer.get_float()]
	var state := TrackingState.new()
	state.timestamp = timestamp
	if translation.size() >= 2:
		state.head_pos = Vector2(float(translation[0]), -float(translation[1]))
	if euler.size() >= 3:
		state.head_rot = deg_to_rad(float(euler[2]))
	state.eye_blink_l = clamp(float(blink_left), 0.0, 1.0)
	state.eye_blink_r = clamp(float(blink_right), 0.0, 1.0)
	state.confidence = success ? clamp(1.0 - float(pnp_error), 0.0, 1.0) : 0.0
	var possible_landmarks := int(min(BINARY_LANDMARKS, buffer.get_available_bytes() / 12))
	if possible_landmarks > 0:
		var pts := PackedVector2Array()
		for i in possible_landmarks:
			buffer.get_float() # confidence per landmark
			if buffer.get_available_bytes() < 8:
				break
			var y := buffer.get_float()
			var x := buffer.get_float()
			pts.append(Vector2(x, y))
		state.landmarks = pts
	# If multiple faces were packed, we only consume the first one; the default sender typically sends one face per packet.
	if expected_face_id != 0 and face_id != expected_face_id:
		return null
	return state

func _parse_json(data: Dictionary) -> TrackingState:
	var faces: Array = data.get("faces", data.get("data", []))
	if faces.is_empty():
		return null
	var face: Dictionary = faces[0]
	for entry in faces:
		if entry.get("id", 0) == expected_face_id:
			face = entry
			break
	var state := TrackingState.new()
	var translation: Array = face.get("translation", face.get("trans", [0.0, 0.0, 0.0]))
	if translation.size() >= 2:
		state.head_pos = Vector2(float(translation[0]), -float(translation[1]))
	var euler: Array = face.get("euler", face.get("rotation", [0.0, 0.0, 0.0]))
	if euler.size() >= 3:
		state.head_rot = deg_to_rad(float(euler[2]))
	var blink: Array = face.get("eye_blink", face.get("blink", [0.0, 0.0]))
	if blink.size() >= 2:
		state.eye_blink_l = clamp(float(blink[0]), 0.0, 1.0)
		state.eye_blink_r = clamp(float(blink[1]), 0.0, 1.0)
	var mouth = face.get("mouth", face.get("mouth_open", face.get("mouth_height", 0.0)))
	if typeof(mouth) == TYPE_ARRAY and mouth.size() > 0:
		state.mouth_open = clamp(float(mouth[0]), 0.0, 1.0)
	elif typeof(mouth) in [TYPE_FLOAT, TYPE_INT]:
		state.mouth_open = clamp(float(mouth), 0.0, 1.0)
	state.confidence = float(face.get("score", data.get("conf", 1.0)))
	var landmarks_data = face.get("landmarks", face.get("lm", []))
	if typeof(landmarks_data) == TYPE_ARRAY and not landmarks_data.is_empty():
		var pts := PackedVector2Array()
		if typeof(landmarks_data[0]) in [TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY]:
			for pair in landmarks_data:
				if pair.size() >= 2:
					pts.append(Vector2(float(pair[0]), float(pair[1])))
		else:
			for i in range(0, landmarks_data.size(), 2):
				pts.append(Vector2(float(landmarks_data[i]), float(landmarks_data[i + 1])))
		state.landmarks = pts
	state.timestamp = Time.get_unix_time_from_system()
	return state

func is_running() -> bool:
	return _running

func time_since_last_packet() -> float:
	return Time.get_unix_time_from_system() - _last_packet_time

extends Resource
class_name TrackingState

var head_pos: Vector2 = Vector2.ZERO
var head_rot: float = 0.0
var eye_blink_l: float = 0.0
var eye_blink_r: float = 0.0
var mouth_open: float = 0.0
var confidence: float = 0.0
var timestamp: float = 0.0
var packet_rate: float = 0.0
var landmarks: PackedVector2Array = PackedVector2Array()

func clone() -> TrackingState:
	var c := TrackingState.new()
	c.head_pos = head_pos
	c.head_rot = head_rot
	c.eye_blink_l = eye_blink_l
	c.eye_blink_r = eye_blink_r
	c.mouth_open = mouth_open
	c.confidence = confidence
	c.timestamp = timestamp
	c.packet_rate = packet_rate
	c.landmarks = landmarks.duplicate()
	return c

func reset() -> void:
	head_pos = Vector2.ZERO
	head_rot = 0.0
	eye_blink_l = 0.0
	eye_blink_r = 0.0
	mouth_open = 0.0
	confidence = 0.0
	packet_rate = 0.0
	landmarks = PackedVector2Array()
	timestamp = Time.get_unix_time_from_system()

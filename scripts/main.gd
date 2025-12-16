extends Node2D

@export var idle_timeout := 0.75
@export var idle_bob_amplitude := 6.0
@export var idle_bob_speed := 1.0
@export var idle_blink_interval := 3.5
@export var idle_blink_duration := 0.15
@export var idle_breath_mouth := 0.08
@export var position_smooth := 0.15
@export var rotation_smooth := 0.18
@export var expression_smooth := 0.2
@export var neutral_gravity := 0.05

var receiver: NetworkReceiver
var avatar: Avatar
var _last_state := TrackingState.new()
var _smoothed_state := TrackingState.new()
var _neutral_state := TrackingState.new()
var _calibration := TrackingState.new()
var _last_packet_time := -INF
var _use_chroma := false
var _idle_time := 0.0
var _was_idle := false

var _ui := {}

func _ready() -> void:
	_build_scene()
	_apply_background()

func _build_scene() -> void:
	avatar = Avatar.new()
	avatar.position = Vector2(360, 640)
	add_child(avatar)

	receiver = NetworkReceiver.new()
	receiver.auto_start = false
	add_child(receiver)
	receiver.tracking_updated.connect(_on_tracking)

	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := Panel.new()
	panel.name = "Panel"
	panel.size = Vector2(300, 280)
	panel.position = Vector2(16, 16)
	layer.add_child(panel)

	var vb := VBoxContainer.new()
	vb.anchor_right = 1
	vb.anchor_bottom = 1
	vb.offset_left = 10
	vb.offset_top = 10
	vb.offset_right = -10
	vb.offset_bottom = -10
	panel.add_child(vb)

	var title := Label.new()
	title.text = "OpenSeeFace VTuber PoC"
	title.add_theme_font_size_override("font_size", 16)
	vb.add_child(title)

	vb.add_child(_labeled_field("IP", "127.0.0.1", "ip"))
	vb.add_child(_labeled_spin("Port", 11573, "port"))

	var hb := HBoxContainer.new()
	var start_btn := Button.new()
	start_btn.text = "Start"
	start_btn.pressed.connect(_on_start)
	hb.add_child(start_btn)
	var stop_btn := Button.new()
	stop_btn.text = "Stop"
	stop_btn.pressed.connect(_on_stop)
	hb.add_child(stop_btn)
	vb.add_child(hb)

	var calibrate := Button.new()
	calibrate.text = "Calibrate neutral"
	calibrate.pressed.connect(_on_calibrate)
	vb.add_child(calibrate)

	var debug_cb := CheckBox.new()
	debug_cb.text = "Debug landmarks"
	debug_cb.toggled.connect(func(value):
		avatar.debug_draw = value
	)
	vb.add_child(debug_cb)

	var chroma_cb := CheckBox.new()
	chroma_cb.text = "Use green background"
	chroma_cb.toggled.connect(func(value):
		_use_chroma = value
		_apply_background()
	)
	vb.add_child(chroma_cb)

	var import_btn := Button.new()
	import_btn.text = "Import character"
	import_btn.pressed.connect(_on_import_character)
	vb.add_child(import_btn)

	var reset_btn := Button.new()
	reset_btn.text = "Reset to stick figure"
	reset_btn.pressed.connect(_on_reset_character)
	vb.add_child(reset_btn)

	var status := Label.new()
	status.text = "Idle"
	status.name = "status"
	vb.add_child(status)

	var packet := Label.new()
	packet.name = "packet"
	packet.text = "Packets: 0"
	vb.add_child(packet)

	_ui["status"] = status
	_ui["packet"] = packet

	var file_dialog := FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.tscn,*.scn ; Scenes", "*.res ; PackedScene", "*.png,*.jpg,*.jpeg,*.webp ; Textures"])
	file_dialog.title = "Select character asset"
	file_dialog.file_selected.connect(_on_character_selected)
	layer.add_child(file_dialog)
	_ui["file_dialog"] = file_dialog

func _labeled_field(label_text: String, default_value: String, key: String) -> Control:
	var hb := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 80
	hb.add_child(lbl)
	var line := LineEdit.new()
	line.text = default_value
	hb.add_child(line)
	_ui[key] = line
	return hb

func _labeled_spin(label_text: String, default_value: int, key: String) -> Control:
	var hb := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 80
	hb.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 65535
	spin.step = 1
	spin.value = default_value
	hb.add_child(spin)
	_ui[key] = spin
	return hb

func _apply_background() -> void:
	var vp := get_viewport()
	vp.transparent_bg = not _use_chroma
	if _use_chroma:
		VisualServer.set_default_clear_color(Color(0, 1, 0, 1))
	else:
		VisualServer.set_default_clear_color(Color(0, 0, 0, 0))

func _on_start() -> void:
	var ip := _ui.ip.text
	var port := int(_ui.port.value)
	receiver.start(ip, port)
	_ui.status.text = "Listening on %s:%d" % [ip, port]

func _on_stop() -> void:
	receiver.stop()
	_ui.status.text = "Stopped"
	_last_packet_time = -INF

func _on_calibrate() -> void:
	_calibration = _smoothed_state.clone()

func _on_import_character() -> void:
	var fd: FileDialog = _ui.file_dialog
	fd.popup_centered_ratio()

func _on_reset_character() -> void:
	avatar.clear_custom_character()
	_ui.status.text = "Using stick figure"

func _on_tracking(state: TrackingState) -> void:
	_last_state = _apply_calibration(state)
	_last_packet_time = state.timestamp
	_idle_time = 0.0
	_was_idle = false
	_ui.status.text = "Tracking (conf %.2f)" % state.confidence
	_ui.packet.text = "Packets: %.1f/s" % state.packet_rate

func _on_character_selected(path: String) -> void:
	var res := ResourceLoader.load(path)
	if res is PackedScene:
		avatar.set_custom_scene(res)
		_ui.status.text = "Custom scene loaded"
	elif res is Texture2D:
		avatar.set_custom_texture(res)
		_ui.status.text = "Custom texture loaded"
	else:
		push_warning("Unsupported character asset: %s" % path)
		_ui.status.text = "Unsupported import"

func _apply_calibration(state: TrackingState) -> TrackingState:
	var s := state.clone()
	s.head_pos -= _calibration.head_pos
	s.head_rot -= _calibration.head_rot
	s.eye_blink_l = clamp(state.eye_blink_l - _calibration.eye_blink_l, 0.0, 1.0)
	s.eye_blink_r = clamp(state.eye_blink_r - _calibration.eye_blink_r, 0.0, 1.0)
	s.mouth_open = clamp(state.mouth_open - _calibration.mouth_open, 0.0, 1.0)
	return s

func _process(delta: float) -> void:
	_idle_time += delta
	var now := Time.get_unix_time_from_system()
	var target := _last_state
	var idle_mode := now - _last_packet_time > idle_timeout
	if idle_mode:
		target = _build_idle_state()
		if not _was_idle:
			_ui.status.text = "Idle (no tracking)"
		_was_idle = true
	else:
		_was_idle = false
	_smoothed_state.head_pos = _smoothed_state.head_pos.lerp(target.head_pos, position_smooth)
	_smoothed_state.head_rot = lerp_angle(_smoothed_state.head_rot, target.head_rot, rotation_smooth)
	_smoothed_state.eye_blink_l = lerp(_smoothed_state.eye_blink_l, target.eye_blink_l, expression_smooth)
	_smoothed_state.eye_blink_r = lerp(_smoothed_state.eye_blink_r, target.eye_blink_r, expression_smooth)
	_smoothed_state.mouth_open = lerp(_smoothed_state.mouth_open, target.mouth_open, expression_smooth)
	_smoothed_state.confidence = target.confidence
	_smoothed_state.landmarks = target.landmarks
	avatar.set_state(_smoothed_state, target.landmarks, _use_chroma)

func _build_idle_state() -> TrackingState:
	var idle := _neutral_state.clone()
	var bob := sin(_idle_time * TAU * idle_bob_speed) * idle_bob_amplitude
	idle.head_pos.y += bob
	idle.head_rot = lerp_angle(_smoothed_state.head_rot, sin(_idle_time * 0.7) * 0.08, neutral_gravity)
	var blink_phase := fmod(_idle_time, idle_blink_interval)
	var blinking := blink_phase < idle_blink_duration
	idle.eye_blink_l = 1.0 if blinking else 0.0
	idle.eye_blink_r = 1.0 if blinking else 0.0
	idle.mouth_open = idle_breath_mouth * (0.5 + 0.5 * sin(_idle_time * 0.8))
	idle.confidence = 0.0
	idle.landmarks = PackedVector2Array()
	return idle

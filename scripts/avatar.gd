extends Node2D
class_name Avatar

@export var head_radius := 32.0
@export var eye_offset := Vector2(14, -6)
@export var eye_radius := Vector2(6, 4)
@export var mouth_width := 24.0
@export var body_height := 64.0
@export var limb_length := 36.0
@export var line_color := Color.WHITE
@export var chroma_color := Color(0, 1, 0)
@export var debug_draw := false

var _state := TrackingState.new()
var _landmarks: PackedVector2Array = PackedVector2Array()
var _background_chroma := false
var _custom_root: Node2D
var _custom_head: Node2D
var _custom_left_eye: Node2D
var _custom_right_eye: Node2D
var _custom_mouth: Node2D

func set_state(state: TrackingState, landmarks: PackedVector2Array, use_chroma := false) -> void:
    _state = state.clone()
    _landmarks = landmarks
    _background_chroma = use_chroma
    _update_custom_pose()
    queue_redraw()

func _draw() -> void:
    var bg_color := Color(0, 0, 0, 0)
    if _background_chroma:
        bg_color = chroma_color
    # draw oversized rect to ensure OBS chroma capture
    draw_rect(Rect2(Vector2(-1000, -1000), Vector2(2000, 2000)), bg_color, true)
    if _custom_root:
        _draw_debug_landmarks()
        return
    var head_center: Vector2 = Vector2(0, -body_height * 0.5) + _state.head_pos * 0.75
    var base: Vector2 = Vector2.ZERO
    var neck: Vector2 = head_center
    draw_set_transform(head_center, _state.head_rot, Vector2.ONE)
    draw_circle(Vector2.ZERO, head_radius, line_color)
    var eye_scale_l: float = clamp(1.0 - _state.eye_blink_l, 0.1, 1.0)
    var eye_scale_r: float = clamp(1.0 - _state.eye_blink_r, 0.1, 1.0)
    _draw_ellipse(eye_offset * Vector2(-1, 1), eye_radius * Vector2(1, eye_scale_l), line_color)
    _draw_ellipse(eye_offset, eye_radius * Vector2(1, eye_scale_r), line_color)
    var mouth_open_offset: float = clamp(_state.mouth_open, 0.0, 1.0) * 10.0
    draw_line(Vector2(-mouth_width * 0.5, mouth_open_offset * -0.5), Vector2(mouth_width * 0.5, mouth_open_offset * -0.5), line_color, 2.0)
    draw_line(Vector2(-mouth_width * 0.25, mouth_open_offset * 0.5), Vector2(mouth_width * 0.25, mouth_open_offset * 0.5), line_color, 2.0)
    draw_set_transform(Vector2.ZERO)
    draw_line(base, neck, line_color, 3.0)
    var hip := base + Vector2(0, body_height)
    draw_line(neck, hip, line_color, 3.0)
    draw_line(neck, neck + Vector2(-limb_length, limb_length * 0.3), line_color, 3.0)
    draw_line(neck, neck + Vector2(limb_length, limb_length * 0.3), line_color, 3.0)
    draw_line(hip, hip + Vector2(-limb_length * 0.6, limb_length), line_color, 3.0)
    draw_line(hip, hip + Vector2(limb_length * 0.6, limb_length), line_color, 3.0)
    _draw_debug_landmarks()

func _draw_ellipse(center: Vector2, radii: Vector2, color: Color, segments: int = 32, width: float = 2.0) -> void:
    var points: PackedVector2Array = PackedVector2Array()
    for i in segments:
        var angle := TAU * float(i) / float(segments)
        var point := Vector2(cos(angle), sin(angle)) * radii + center
        points.append(point)
    if points.is_empty():
        return
    points.append(points[0])
    draw_polyline(points, color, width)

func _draw_debug_landmarks() -> void:
    if debug_draw and not _landmarks.is_empty():
        for p in _landmarks:
            draw_circle(p, 1.5, Color(1, 0.6, 0.2))

func _update_custom_pose() -> void:
    if not _custom_root:
        return
    var head_center: Vector2 = Vector2(0, -body_height * 0.5) + _state.head_pos * 0.75
    if _custom_head:
        _custom_head.position = head_center
        _custom_head.rotation = _state.head_rot
    else:
        _custom_root.position = head_center
        _custom_root.rotation = _state.head_rot
    if _custom_left_eye:
        _custom_left_eye.scale.y = clamp(1.0 - _state.eye_blink_l, 0.1, 1.0)
    if _custom_right_eye:
        _custom_right_eye.scale.y = clamp(1.0 - _state.eye_blink_r, 0.1, 1.0)
    if _custom_mouth:
        _custom_mouth.scale.y = 0.5 + clamp(_state.mouth_open, 0.0, 1.0)

func set_custom_scene(scene: PackedScene) -> void:
    clear_custom_character()
    if not scene:
        return
    var inst := scene.instantiate()
    if not (inst is Node2D):
        push_warning("Custom character root must be a Node2D")
        return
    _custom_root = inst
    _custom_root.position = Vector2.ZERO
    add_child(_custom_root)
    _custom_head = _find_named_node(["Head", "head"], _custom_root)
    _custom_left_eye = _find_named_node(["LeftEye", "EyeLeft", "EyeL", "eye_left"], _custom_root)
    _custom_right_eye = _find_named_node(["RightEye", "EyeRight", "EyeR", "eye_right"], _custom_root)
    _custom_mouth = _find_named_node(["Mouth", "mouth"], _custom_root)
    _update_custom_pose()
    queue_redraw()

func set_custom_texture(texture: Texture2D) -> void:
    clear_custom_character()
    if not texture:
        return
    var root := Node2D.new()
    var sprite := Sprite2D.new()
    sprite.texture = texture
    sprite.centered = true
    sprite.scale = Vector2.ONE
    root.add_child(sprite)
    _custom_head = root
    _custom_root = root
    add_child(_custom_root)
    _update_custom_pose()
    queue_redraw()

func clear_custom_character() -> void:
    if _custom_root and is_instance_valid(_custom_root):
        _custom_root.queue_free()
    _custom_root = null
    _custom_head = null
    _custom_left_eye = null
    _custom_right_eye = null
    _custom_mouth = null
    queue_redraw()

func _find_named_node(names: Array, root: Node) -> Node2D:
    for name in names:
        var node := root.get_node_or_null(name)
        if node and node is Node2D:
            return node
    return null

extends Control
class_name InputVisualizer

@export_group("Appearance")
@export var inactive_color := Color(0.075, 0.065, 0.11, 0.76)
@export var active_color := Color(0.56, 0.37, 0.82, 0.96)
@export var inactive_text_color := Color(0.79, 0.75, 0.87, 1.0)
@export var active_text_color := Color(1.0, 0.96, 1.0, 1.0)
@export var panel_color := Color(0.035, 0.03, 0.06, 0.48)
@export_range(0.0, 30.0, 0.5) var color_transition_speed := 18.0

@onready var _background: PanelContainer = $Background
@onready var _keys := {
	"W": $Background/Contents/MovementKeys/KeyW,
	"A": $Background/Contents/MovementKeys/KeyA,
	"S": $Background/Contents/MovementKeys/KeyS,
	"D": $Background/Contents/MovementKeys/KeyD,
	"SPACE": $Background/Contents/ActionKeys/KeySpace,
	"E": $Background/Contents/ActionKeys/KeyE,
	"R": $Background/Contents/ActionKeys/KeyR,
}

var _key_codes: Dictionary = {}
var _pressed_states: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key_label in _keys:
		var key_panel := _keys[key_label] as PanelContainer
		key_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var contents := $Background/Contents as VBoxContainer
	contents.add_theme_constant_override("separation", 6)
	var movement_keys := $Background/Contents/MovementKeys as GridContainer
	var action_keys := $Background/Contents/ActionKeys as HBoxContainer
	movement_keys.add_theme_constant_override("h_separation", 5)
	movement_keys.add_theme_constant_override("v_separation", 5)
	action_keys.add_theme_constant_override("separation", 5)
	_key_codes = {
		"W": KEY_W,
		"A": _mapped_physical_key("move_left", KEY_A),
		"S": KEY_S,
		"D": _mapped_physical_key("move_right", KEY_D),
		"SPACE": _mapped_physical_key("jump", KEY_SPACE),
		"E": KEY_E,
		"R": KEY_R,
	}
	for key_label in _keys:
		var key_panel := _keys[key_label] as PanelContainer
		var key_text := key_panel.get_node("Label") as Label
		key_text.text = key_label
		key_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key_text.add_theme_color_override("font_color", Color.WHITE)
		_pressed_states[key_label] = false
		_apply_key_style(key_panel, inactive_color, false)
	_apply_background_style()

func _process(_delta: float) -> void:
	for key_label in _keys:
		var pressed := _key_is_pressed(_key_codes[key_label])
		if pressed == _pressed_states[key_label]:
			continue
		_pressed_states[key_label] = pressed
		var key_panel := _keys[key_label] as PanelContainer
		var target: Color = active_color if pressed else inactive_color
		_apply_key_style(key_panel, target, pressed)
		var key_text := key_panel.get_node("Label") as Label
		var tween := create_tween()
		var transition_time := 1.0 / maxf(color_transition_speed, 1.0)
		tween.tween_property(key_text, "self_modulate", active_text_color if pressed else inactive_text_color, transition_time)

func _mapped_physical_key(action: StringName, fallback: Key) -> Key:
	if not InputMap.has_action(action):
		return fallback
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			if key_event.physical_keycode != KEY_NONE:
				return key_event.physical_keycode
			if key_event.keycode != KEY_NONE:
				return key_event.keycode
	return fallback

func _key_is_pressed(key_code: Key) -> bool:
	return Input.is_physical_key_pressed(key_code) or Input.is_key_pressed(key_code)

func _apply_key_style(key_panel: PanelContainer, color: Color, pressed: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.73, 0.63, 0.9, 0.95 if pressed else 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	key_panel.add_theme_stylebox_override("panel", style)

func _apply_background_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = panel_color
	style.border_color = Color(0.48, 0.39, 0.62, 0.48)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	_background.add_theme_stylebox_override("panel", style)

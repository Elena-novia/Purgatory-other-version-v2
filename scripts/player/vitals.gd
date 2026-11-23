extends Node
class_name PlayerVitals

signal values_changed(health: float, sanity: float)
signal died(cause: String)

@export_range(0.0, 1.0) var max_health := 1.0
@export_range(0.0, 1.0) var max_sanity := 1.0
@export_range(0.0, 1.0) var damage_per_hit := 0.1
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:%/s") var sanity_drain_percent_per_second := 7.5
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:%/s") var sanity_regen_percent_per_second := 8.0

var health := 1.0
var sanity := 1.0
var orb_is_away := false
var _dead := false

func _ready() -> void:
	health = max_health
	sanity = max_sanity

func _process(delta: float) -> void:
	if _dead:
		return
	if orb_is_away:
		sanity = maxf(0.0, sanity - sanity_drain_percent_per_second * 0.01 * delta)
	else:
		sanity = minf(max_sanity, sanity + sanity_regen_percent_per_second * 0.01 * delta)
	sanity = clampf(sanity, 0.0, max_sanity)
	_emit_values()
	_check_death()

func take_damage(amount: float = -1.0) -> void:
	if _dead:
		return
	health = maxf(0.0, health - (damage_per_hit if amount < 0.0 else amount))
	_emit_values()
	_check_death()

func restore() -> void:
	_restore_values()
	_emit_values()

func _restore_values() -> void:
	_dead = false
	health = max_health
	sanity = max_sanity
	orb_is_away = false

func _emit_values() -> void:
	values_changed.emit(health, sanity)

func _check_death() -> void:
	if _dead:
		return
	if health <= 0.0:
		_dead = true
		died.emit("physical")
	elif sanity <= 0.0:
		_dead = true
		died.emit("sanity")

extends CanvasLayer
class_name GameHUD

@onready var artwork: TextureRect = $VitalsPanel/Artwork
@onready var sanity_particles: CPUParticles2D = $VitalsPanel/Artwork/SanityParticles
@onready var damage_flash: ColorRect = $DamageFlash
@onready var death_canvas: Control = $DeathCanvas
@onready var death_overlay: ColorRect = $DeathCanvas/DeathOverlay
@onready var death_splash: ColorRect = $DeathCanvas/DeathSplash
@onready var death_text: Label = $DeathCanvas/DeathSplash/StatusTop
@onready var layer_input_notice: Label = $LayerInputNotice
var _damage_tween: Tween
var _death_tween: Tween
var _layer_input_notice_tween: Tween

func _ready() -> void:
	death_canvas.resized.connect(_layout_death_splash)
	_layout_death_splash()
	reset_death_effects()
	damage_flash.color.a = 0.0

func _layout_death_splash() -> void:
	var side := minf(death_canvas.size.x, death_canvas.size.y) * 0.84
	death_splash.size = Vector2.ONE * side
	death_splash.position = (death_canvas.size - death_splash.size) * 0.5

func update_vitals(health: float, sanity: float) -> void:
	var artwork_material := artwork.material as ShaderMaterial
	var sanity_ratio := clampf(sanity, 0.0, 1.0)
	artwork_material.set_shader_parameter("health_ratio", clampf(health, 0.0, 1.0))
	artwork_material.set_shader_parameter("sanity_ratio", sanity_ratio)
	# The particle source follows the sanity bar's scaled bounds and moving drain edge.
	sanity_particles.position = Vector2(
		artwork.size.x * (404.0 + 356.0 * sanity_ratio) / 1024.0,
		artwork.size.y * 116.0 / 256.0
	)

func set_sanity_draining(is_draining: bool) -> void:
	sanity_particles.emitting = is_draining

func show_layer_input_backlog_full() -> void:
	if _layer_input_notice_tween:
		_layer_input_notice_tween.kill()
	layer_input_notice.show()
	_layer_input_notice_tween = create_tween()
	_layer_input_notice_tween.tween_interval(1.6)
	_layer_input_notice_tween.tween_callback(layer_input_notice.hide)

func show_damage() -> void:
	if _damage_tween and _damage_tween.is_running():
		_damage_tween.kill()
	damage_flash.color.a = 0.72
	_damage_tween = create_tween()
	_damage_tween.tween_property(damage_flash, "color:a", 0.0, 0.55)

func show_death(cause: String) -> void:
	if _death_tween and _death_tween.is_running():
		_death_tween.kill()
	death_overlay.visible = true
	death_splash.visible = true
	death_overlay.color.a = 0.0
	death_splash.color.a = 0.0
	death_text.text = "PHYSICAL DEATH" if cause == "physical" else "SANITY LOST"
	death_text.modulate.a = 1.0
	_death_tween = create_tween()
	if cause == "physical":
		_death_tween.tween_property(death_overlay, "color:a", 1.0, 0.45)
		_death_tween.tween_property(death_splash, "color:a", 0.9, 0.08)
		# Keep the completed health effect visible for the remainder of the
		# existing 2.5 second death hold.
		await get_tree().create_timer(2.5).timeout
	else:
		_death_tween.tween_property(death_overlay, "color:a", 1.0, 3.0)
		# Do not reset the extinguishing effect before its three second tween
		# has completed; main.gd waits for this function before respawning.
		await _death_tween.finished

func reset_death_effects() -> void:
	if _death_tween and _death_tween.is_running():
		_death_tween.kill()
	death_overlay.color.a = 0.0
	death_splash.color.a = 0.0
	death_text.modulate.a = 0.0
	death_text.text = ""
	death_overlay.visible = false
	death_splash.visible = false
	damage_flash.color.a = 0.0
	if _damage_tween and _damage_tween.is_running():
		_damage_tween.kill()

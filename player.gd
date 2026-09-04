extends CharacterBody2D

# ==============================================================================
# БЛОКНОТ ДАННЫХ (ДОГМА №6: DATA-ORIENTED DESIGN)
# ==============================================================================
var player_speed: float = 300.0
var srv_damage: float = 15.0
var srv_punch_cooldown: float = 0.4
var srv_cooldown_timer: float = 0.0

var owner_id: int = 0
var server_raycast: RayCast2D = null
var player_camera: Camera2D = null

var srv_input_direction: Vector2 = Vector2.ZERO
var srv_target_rotation: float = 0.0
var srv_wants_to_punch: bool = false

# ==============================================================================
# КУЛАКИ / УДАР (визуал + хитбокс)
# ==============================================================================
const FIST_BASE_ANGLE: float = deg_to_rad(75.0)   # смещение кулаков от направления взгляда в покое
const FIST_DIST_BASE: float = 36.0                # расстояние кулака от центра тела в покое (тело ~32px радиусом)
const FIST_PUNCH_EXTRA_DIST: float = 20.0         # насколько кулак выезжает вперёд при ударе
const FIST_PUNCH_ANGLE_TARGET: float = deg_to_rad(10.0) # к какому углу стягивается активный кулак
const PUNCH_DURATION: float = 0.22                # секунд на полный цикл удара (вперёд-назад)

var fist1: Node2D = null
var fist2: Node2D = null
var punch_hitbox: Area2D = null
var punch_hitbox_shape: CollisionShape2D = null

var is_punching: bool = false
var punch_elapsed: float = 0.0
var active_fist: int = 1        # 1 или 2 — чередуем удары, как в оригинале
var punch_already_hit: bool = false
var walk_wobble_time: float = 0.0

# Для логирования движения (не спамить каждый кадр)
var _last_logged_position: Vector2 = Vector2.ZERO

# ==============================================================================
# ДОГМА №5: ИЗОЛИРОВАННЫЙ СИСТЕМНЫЙ ЛОГГЕР ЧЕРНОГО ЯЩИКА
# ==============================================================================
class GameLogger:
	static var log_buffer: Array[String] = []
	
	static func log_event(message: String) -> void:
		var time = Time.get_time_string_from_system()
		var log_string = "[%s] %s" % [time, message]
		print(log_string)
		log_buffer.append(log_string)
		
		if log_buffer.size() >= 10 or "[SYSTEM]" in message:
			flush_to_disk()
			
	static func flush_to_disk() -> void:
		if log_buffer.is_empty(): return
		var file = FileAccess.open("user://game_log.txt", FileAccess.READ_WRITE)
		if not file:
			file = FileAccess.open("user://game_log.txt", FileAccess.WRITE)
		if file:
			file.seek_end()
			for line in log_buffer:
				file.store_string(line + "\n")
			file.close()
			log_buffer.clear()

func _ready() -> void:
	GameLogger.log_event("[SYSTEM] Сетевой объект персонажа успешно инициализирован.")
	
	server_raycast = get_node_or_null("RayCast2D")
	player_camera = get_node_or_null("Camera2D")

	fist1 = get_node_or_null("Fist1")
	fist2 = get_node_or_null("Fist2")
	punch_hitbox = get_node_or_null("PunchHitbox")
	if punch_hitbox:
		punch_hitbox_shape = punch_hitbox.get_node_or_null("CollisionShape2D")
		punch_hitbox.body_entered.connect(_on_punch_hitbox_body_entered)
	
	GameLogger.log_event("[PLAYER] Игрок загружен. ID: %s, Камера: %s" % [name, "есть" if player_camera else "нет"])
	
	if server_raycast:
		server_raycast.add_exception(self)
		
	if name.is_valid_int():
		owner_id = int(str(name))
	
	var my_local_id = multiplayer.get_unique_id()
	if owner_id == my_local_id:
		if is_instance_valid(player_camera):
			player_camera.make_current()
			player_camera.enabled = true
			GameLogger.log_event("[PLAYER] Камера активирована для игрока %s" % name)
	else:
		if is_instance_valid(player_camera):
			player_camera.enabled = false
			GameLogger.log_event("[PLAYER] Камера отключена для игрока %s" % name)

func _physics_process(delta: float) -> void:
	rotation = srv_target_rotation
	velocity = srv_input_direction * player_speed
	move_and_slide()

	_update_punch_state(delta)
	_update_fists_visual(delta)
	
	# Логируем движение РЕЖЕ (раз в 2 секунды ИЛИ при сильном перемещении)
	if multiplayer.is_server():
		if not has_meta("last_log_time"):
			set_meta("last_log_time", 0.0)
		
		var last_log_time = get_meta("last_log_time")
		var time_passed = Time.get_ticks_msec() / 1000.0 - last_log_time
		
		var distance = global_position.distance_to(_last_logged_position)
		if (time_passed > 2.0 or distance > 100.0) and distance > 1.0:
			GameLogger.log_event("[PLAYER] Игрок %s переместился на %s" % [name, global_position])
			_last_logged_position = global_position
			set_meta("last_log_time", Time.get_ticks_msec() / 1000.0)
	
	if multiplayer.is_server():
		_rpc_sync_position_to_clients.rpc(global_position, rotation, srv_input_direction)
		
	var my_local_id = multiplayer.get_unique_id()
	if owner_id == my_local_id:
		_gather_and_send_input()

@rpc("any_peer", "call_local", "unreliable")
func _submit_input_to_server(dir: Vector2, rot: float, punch: bool) -> void:
	if multiplayer.get_remote_sender_id() == owner_id:
		srv_input_direction = dir
		srv_target_rotation = rot
		srv_wants_to_punch = punch

@rpc("any_peer", "unreliable")
func _rpc_sync_position_to_clients(server_pos: Vector2, server_rot: float, server_dir: Vector2) -> void:
	if multiplayer.is_server(): return
	global_position = server_pos
	rotation = server_rot
	srv_input_direction = server_dir

func _gather_and_send_input() -> void:
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down").normalized()
	var wants_punch = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var mouse_pos = get_global_mouse_position()
	var target_rot = (mouse_pos - global_position).angle()
	
	srv_input_direction = input_dir
	srv_target_rotation = target_rot
	srv_wants_to_punch = wants_punch
	
	if wants_punch:
		GameLogger.log_event("[PLAYER] Игрок %s атакует!" % name)
	
	if not multiplayer.is_server():
		_submit_input_to_server.rpc(input_dir, target_rot, wants_punch)

## Запускает/продолжает цикл удара и включает хитбокс в нужный момент.
## Анимация кулаков идёт локально у всех, кто видит игрока (это чисто визуал),
## а урон наносит только сервер (см. _on_punch_hitbox_body_entered).
func _update_punch_state(delta: float) -> void:
	if srv_cooldown_timer > 0.0:
		srv_cooldown_timer -= delta

	if not is_punching and srv_wants_to_punch and srv_cooldown_timer <= 0.0:
		is_punching = true
		punch_elapsed = 0.0
		punch_already_hit = false
		active_fist = 2 if active_fist == 1 else 1  # чередуем руки
		srv_cooldown_timer = srv_punch_cooldown

	if is_punching:
		punch_elapsed += delta
		var t: float = clamp(punch_elapsed / PUNCH_DURATION, 0.0, 1.0)
		# треугольная кривая: 0 -> 1 (первая половина) -> 0 (вторая половина)
		var progress: float = 1.0 - abs(t * 2.0 - 1.0)

		if punch_hitbox_shape:
			punch_hitbox.position = Vector2.RIGHT * (FIST_DIST_BASE + progress * FIST_PUNCH_EXTRA_DIST)
			punch_hitbox_shape.disabled = progress < 0.5  # хитбокс активен только у пика удара

		if t >= 1.0:
			is_punching = false
			if punch_hitbox_shape:
				punch_hitbox_shape.disabled = true
	else:
		if punch_hitbox_shape and not punch_hitbox_shape.disabled:
			punch_hitbox_shape.disabled = true


## Считает локальные позиции кулаков: покачивание при ходьбе + вынос вперёд у бьющего кулака.
func _update_fists_visual(delta: float) -> void:
	if not fist1 or not fist2:
		return

	walk_wobble_time += delta * 8.0
	var move_amount: float = clamp(srv_input_direction.length(), 0.0, 1.0)
	var wobble: float = sin(walk_wobble_time) * deg_to_rad(12.0) * move_amount

	var punch_t: float = 0.0
	if is_punching:
		var t: float = clamp(punch_elapsed / PUNCH_DURATION, 0.0, 1.0)
		punch_t = 1.0 - abs(t * 2.0 - 1.0)

	_place_fist(fist1, 1, wobble, punch_t)
	_place_fist(fist2, 2, wobble, punch_t)


func _place_fist(fist: Node2D, fist_index: int, wobble: float, punch_t: float) -> void:
	var is_active: bool = is_punching and active_fist == fist_index
	var side: float = 1.0 if fist_index == 1 else -1.0

	var base_angle: float = side * FIST_BASE_ANGLE + wobble
	var angle: float = base_angle
	var dist: float = FIST_DIST_BASE

	if is_active:
		angle = lerp(base_angle, side * FIST_PUNCH_ANGLE_TARGET, punch_t)
		dist = FIST_DIST_BASE + punch_t * FIST_PUNCH_EXTRA_DIST

	fist.position = Vector2.RIGHT.rotated(angle) * dist


func _on_punch_hitbox_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	if punch_already_hit:
		return
	if body == self:
		return
	if body.has_method("server_take_damage"):
		punch_already_hit = true
		body.server_take_damage(srv_damage)
		GameLogger.log_event("[PLAYER] Игрок %s ударил %s" % [name, body.name])


func server_take_damage(amount: float) -> void:
	if not multiplayer.is_server(): return
	GameLogger.log_event("[SERVER] Игрок %s получил %f урона!" % [name, amount])
	
	# Пример проверки на смерть (если у тебя есть переменная health)
	# if health <= 0:
	#     GameLogger.log_event("[SERVER] Игрок %s УБИТ!" % name)ф

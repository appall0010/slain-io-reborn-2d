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
		if srv_cooldown_timer > 0.0: srv_cooldown_timer -= delta
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
	
	if wants_punch and not multiplayer.is_server():
		GameLogger.log_event("[PLAYER] Игрок %s атакует!" % name)
	
	if not multiplayer.is_server():
		_submit_input_to_server.rpc(input_dir, target_rot, wants_punch)

func server_take_damage(amount: float) -> void:
	if not multiplayer.is_server(): return
	GameLogger.log_event("[SERVER] Игрок %s получил %f урона!" % [name, amount])
	
	# Пример проверки на смерть (если у тебя есть переменная health)
	# if health <= 0:
	#     GameLogger.log_event("[SERVER] Игрок %s УБИТ!" % name)ф

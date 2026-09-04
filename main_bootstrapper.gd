extends Node

enum GameState { BOOT, MAIN_MENU, GAMEPLAY, GAME_OVER }
var current_state: GameState = GameState.BOOT

var active_gameplay_scene: Node = null
var menu_ui_layer: CanvasLayer = null
var network_spawner: MultiplayerSpawner = null

const MAP_SCENE_PATH = "res://main.tscn" 
const PLAYER_SCENE_PATH = "res://player.tscn"
const DEFAULT_PORT = 25565
const DEFAULT_IP = "127.0.0.1"

func _ready() -> void:
	print("🔥 BOOTSTRAPPER ЗАПУЩЕН (AutoLoad)")
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Убеждаемся, что старых подключений нет
	multiplayer.multiplayer_peer = null
	
	network_spawner = MultiplayerSpawner.new()
	network_spawner.name = "GlobalMultiplayerSpawner"
	network_spawner.add_spawnable_scene(PLAYER_SCENE_PATH)
	add_child(network_spawner)
	
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	
	_show_main_menu()

func _show_main_menu() -> void:
	print("🟢 ПОКАЗЫВАЮ МЕНЮ")
	
	if menu_ui_layer:
		menu_ui_layer.queue_free()
		menu_ui_layer = null
	
	menu_ui_layer = CanvasLayer.new()
	add_child(menu_ui_layer)
	
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_ui_layer.add_child(bg)
	
	var panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(400, 300)
	menu_ui_layer.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 200)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	var label = Label.new()
	label.text = "SLAIN.IO REBORN 2D"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(300, 60)
	label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(label)
	
	var host_btn = Button.new()
	host_btn.text = "СОЗДАТЬ СЕРВЕР (HOST)"
	host_btn.custom_minimum_size = Vector2(280, 45)
	host_btn.pressed.connect(_on_host_pressed)
	vbox.add_child(host_btn)
	
	var join_btn = Button.new()
	join_btn.text = "ПОДКЛЮЧИТЬСЯ (CLIENT)"
	join_btn.custom_minimum_size = Vector2(280, 45)
	join_btn.pressed.connect(_on_join_pressed)
	vbox.add_child(join_btn)
	
	print("✅ Меню создано!")

func _on_host_pressed() -> void:
	print("🟣 HOST НАЖАТ")
	if menu_ui_layer:
		menu_ui_layer.visible = false
		print("🔴 Меню скрыто")
	_setup_network_server()

func _on_join_pressed() -> void:
	print("🟣 CLIENT НАЖАТ")
	if menu_ui_layer:
		menu_ui_layer.visible = false
		print("🔴 Меню скрыто")
	_setup_network_client()

func _setup_network_server() -> void:
	print("🟣 _setup_network_server() ВЫЗВАН")
	
	# Принудительно сбрасываем соединение
	if multiplayer.multiplayer_peer != null:
		print("⚠️ Найден старый peer, сбрасываю...")
		multiplayer.multiplayer_peer = null
	
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(DEFAULT_PORT, 32)
	if err != OK:
		print("❌ Не удалось создать сервер, ошибка: ", err)
		return
	
	multiplayer.multiplayer_peer = peer
	print("✅ Сервер создан на порту ", DEFAULT_PORT)
	
	_start_gameplay()
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	print("🟢 СПАВН ИГРОКА ДЛЯ ХОСТА")
	_spawn_player_manually(1)

func _setup_network_client() -> void:
	print("🟣 _setup_network_client() ВЫЗВАН")
	
	# Принудительно сбрасываем соединение
	if multiplayer.multiplayer_peer != null:
		print("⚠️ Найден старый peer, сбрасываю...")
		multiplayer.multiplayer_peer = null
	
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(DEFAULT_IP, DEFAULT_PORT)
	if err != OK:
		print("❌ Не удалось подключиться к серверу, ошибка: ", err)
		return
	
	multiplayer.multiplayer_peer = peer
	print("✅ Клиент подключен к ", DEFAULT_IP, ":", DEFAULT_PORT)
	
	_start_gameplay()

func _start_gameplay() -> void:
	print("🔵 _start_gameplay() ВЫЗВАН")
	
	if active_gameplay_scene:
		active_gameplay_scene.queue_free()
		active_gameplay_scene = null
	
	var map = load(MAP_SCENE_PATH)
	if not map:
		print("❌ Не удалось загрузить карту")
		return
	
	active_gameplay_scene = map.instantiate()
	add_child(active_gameplay_scene)
	
	if network_spawner:
		network_spawner.spawn_path = active_gameplay_scene.get_path()
		print("🟢 Путь спавнера: ", network_spawner.spawn_path)
	
	print("✅ Карта загружена")

func _spawn_player_manually(id: int) -> void:
	print("🟢 РУЧНОЙ СПАВН ИГРОКА ", id)
	
	var player_scene = load(PLAYER_SCENE_PATH)
	if not player_scene:
		print("❌ Не удалось загрузить player.tscn")
		return
	
	var new_player = player_scene.instantiate()
	new_player.name = str(id)
	new_player.z_index = 10  # <- ДОБАВЬ ЭТУ СТРОЧКУ! Она поднимет игрока над сеткой
	new_player.set_multiplayer_authority(id)
	
	# Если в player.tscn нет спрайта, добавь временный
	var sprite_check = new_player.get_node_or_null("Sprite2D")
	if not sprite_check:
		var sprite = Sprite2D.new()
		sprite.texture = load("res://icon.svg")
		sprite.scale = Vector2(0.5, 0.5)
		new_player.add_child(sprite)
	
	if active_gameplay_scene:
		active_gameplay_scene.add_child(new_player)
		new_player.global_position = Vector2(500, 300)
		print("✅ Игрок ", id, " добавлен в карту на позицию ", new_player.global_position)
	else:
		add_child(new_player)
		print("⚠️ Игрок добавлен в бутстраппер (нет карты)")
	
	new_player.add_to_group("players")
	
func _on_player_connected(id: int) -> void:
	print("🔗 Игрок подключился: ", id)
	if multiplayer.is_server():
		_spawn_player_manually(id)

func _on_player_disconnected(id: int) -> void:
	print("🔌 Игрок отключился: ", id)
	if multiplayer.is_server():
		var player = get_node_or_null(str(id))
		if player: player.queue_free()

func _cleanup_gameplay() -> void:
	print("🧹 Очистка игровой сессии")
	for player in get_tree().get_nodes_in_group("players"):
		player.queue_free()
	
	if active_gameplay_scene:
		active_gameplay_scene.queue_free()
		active_gameplay_scene = null
	
	multiplayer.multiplayer_peer = null

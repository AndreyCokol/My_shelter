extends Control

const DistrictEvents = preload("res://game/systems/world/district_events.gd")
const Expedition = preload("res://game/systems/world/expedition_order.gd")
const Camp = preload("res://game/systems/world/camp_network.gd")
const Work = preload("res://game/systems/shelter/resident_work.gd")
const Construction = preload("res://game/systems/shelter/construction.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Gameplay = preload("res://game/systems/gameplay/gameplay_commands.gd")
const Combat = preload("res://game/systems/combat/combat_loadout.gd")
const Art = preload("res://game/ui/asset_theme.gd")
const ExplorationHUD = preload("res://game/ui/exploration_hud.gd")
const RadialMenu = preload("res://game/ui/radial_menu.gd")
const QUEST_TITLES = ["Победить противника", "Вернуться в убежище после первого боя", "Посадить семена", "Собрать урожай", "Найти путников", "Получить согласие", "Заселить двух жителей"]

const ITEM_ICONS = {
	"seed.basic": preload("res://game/assets/project/inventory/seed.svg"),
	"crop.potato": preload("res://game/assets/project/inventory/potato.svg"),
	"tool.basic": preload("res://game/assets/project/inventory/knife.svg"),
	"material.salvage": preload("res://game/assets/project/inventory/salvage.svg"),
	"material.lamp_kit": preload("res://game/assets/project/inventory/lamp_kit.svg"),
}
var inventory_container := "player"
var inventory_selection := ""

var app
var panel_id: String = ""
var pause_token: int = 0
var hud: ExplorationHUD
var radial: RadialMenu
var radial_pause_token := 0
var shelter_nav_button: Button
var shelter_modal_button: Button
var notice: Label
var modal: ColorRect
var body: VBoxContainer
var heading: Label
var heading_icon: TextureRect
var rest_target: int = 0
var building_cell := "0"
var _refresh_pending: bool = false
var _expedition_route_key: Array = []
var _expedition_next_exit := ""
const NAMES = {"hospital": "Больница", "outside": "Город", "shelter": "Убежище", "louvre": "Стоянка"}
const PANELS = {"welcome": "Моё пространственное убежище", "menu": "Пауза", "inventory": "Рюкзак и хранилище", "farm": "Грядки", "rest": "Безопасный отдых", "residents": "Путники", "quests": "Задания", "shop": "Системный магазин", "save": "Сохранение и восстановление", "new_confirm": "Начать заново?", "credits": "Об игре и авторах", "map": "Карта города", "workshop": "Строительство и мастерская", "jobs": "Работа жителей", "camp": "Объявления и торговля", "journal": "Журнал находок", "district_event": "Встреча в районе"}
const STATUS = {"empty": "пусто", "planted": "нужен полив", "growing": "растёт", "ripe": "созрело", "spoiled": "испортилось", "unknown": "не знакомы", "contacted": "готов поговорить", "declined": "отказ", "AWAITING_SUPPLIES": "согласие есть, нужны припасы", "joined": "поселился", "inactive": "не отслеживается", "active": "в работе", "completed": "выполнено"}
const ERRORS = {"INVALID_WORLD_SEED": "Введите целое число от 0 до 2147483647 или оставьте поле пустым.", "OK": "Готово", "ALREADY_APPLIED": "Действие уже выполнено", "UNAVAILABLE": "Сейчас недоступно. Проверьте условия или восстановите сохранение.", "INVALID_STATE": "Состояние изменилось: обновите действие или выберите резервную копию.", "INVALID_ARGUMENT": "Проверьте параметры действия.", "INSUFFICIENT_RESOURCES": "Не хватает доступных ресурсов. Зарезервированная еда не расходуется.", "CAPACITY_EXCEEDED": "В рюкзаке или хранилище не хватает места.", "NEEDS_HOUSING": "Для жильцов нужна свободная кровать.", "REQUIRES_CONSENT": "Сначала нужно добровольное согласие путника.", "STALE_REVISION": "Данные изменились. Экран обновлён — повторите выбор.", "NOT_IN_SAFE_AREA": "Отдых и работа с грядками доступны в убежище.", "SAVE_FAILED": "Не удалось записать сохранение. Действие не подтверждено.", "PAUSED": "Осталась другая причина паузы. Закройте её прежде, чем действовать.", "NOT_FOUND": "Объект не найден."}

# The store display is derived from the exact offer used by A1 transactions.
# Balance changes must never leave a hard-coded amount/price in the UI.
static func offer_description(config: Dictionary, offer_id: String) -> String:
	var offer: Dictionary = config.get("offers", {}).get(offer_id, {})
	var item: Dictionary = config.get("items", {}).get(offer.get("type_id", ""), {})
	if offer.is_empty() or item.is_empty():
		return ""
	return "%d ед. «%s» — %d мон." % [int(offer.get("quantity", 0)), str(item.get("name", "")), int(offer.get("price", 0))]

static func shop_hint(config: Dictionary, offer_id: String) -> String:
	var deal: String = offer_description(config, offer_id)
	if deal.is_empty():
		return "Сейчас нет предложений."
	return deal + " Семена можно найти и в городе. Повторное появление ресурсов — через %d игровых минут." % int(config.get("resource_respawn_minutes", 60))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var theme := Theme.new()
	theme.default_font_size = 13
	var style := StyleBoxFlat.new()
	style.bg_color = Color("21190f")
	style.border_color = Color("b99559")
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	theme.set_stylebox("normal", "Button", style)
	var hover := style.duplicate()
	hover.bg_color = Color("44311b")
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", hover)
	# VIS-02: keep consistent brass pixel frames even when optional vendor UI is present.
	# Vendor icons remain available through Art.icon() but cannot replace golden borders.
	self.theme = theme
	hud = ExplorationHUD.new()
	hud.name = "ExplorationHUD"
	hud.app = app
	hud.panel_requested.connect(open_panel)
	hud.slot_requested.connect(open_quick_slot)
	add_child(hud)
	# Always-visible control between title and top-right minimap (640x360).
	shelter_nav_button = button(self, "Убежище [G]", toggle_shelter)
	shelter_nav_button.name = "ShelterQuickButton"
	shelter_nav_button.position = Vector2(222, 4)
	shelter_nav_button.size = Vector2(132, 25)
	shelter_nav_button.add_theme_font_size_override("font_size", 11)
	shelter_nav_button.focus_mode = Control.FOCUS_NONE
	shelter_nav_button.icon = Art.icon("shelter")
	shelter_nav_button.tooltip_text = "В убежище / вернуться к месту выхода [G]"
	notice = Label.new()
	add_child(notice)
	notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	notice.offset_left = 8
	notice.offset_right = -8
	notice.offset_top = -58
	notice.offset_bottom = -45
	notice.mouse_filter = MOUSE_FILTER_IGNORE
	notice.clip_text = true
	notice.add_theme_font_size_override("font_size", 11)
	notice.add_theme_color_override("font_outline_color", Color("14100d"))
	notice.add_theme_constant_override("outline_size", 3)
	notice.text = "WASD — движение · ЛКМ — удар · Space — уклонение · E — действие · Левый Ctrl — рюкзак по кругу"
	radial = RadialMenu.new()
	radial.name = "RadialMenu"
	radial.chosen.connect(open_quick_slot)
	radial.cancelled.connect(close_radial)
	add_child(radial)
	modal = ColorRect.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.color = Color(0.045, 0.041, 0.028, 0.88)
	add_child(modal)
	var panel := PanelContainer.new()
	panel.position = Vector2(35, 42)
	panel.size = Vector2(570, 290)
	var panelstyle := StyleBoxFlat.new()
	panelstyle.bg_color = Color("211a12")
	panelstyle.border_color = Color("b99559")
	panelstyle.set_border_width_all(1)
	panelstyle.set_corner_radius_all(2)
	panel.add_theme_stylebox_override("panel", panelstyle)
	var panel_art := Art.textured_style("panel_frame", 10, Color(1.0, 0.85, 0.61))
	if panel_art != null:
		panel.add_theme_stylebox_override("panel", panel_art)
	modal.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	var titlebar := HBoxContainer.new()
	box.add_child(titlebar)
	heading_icon = TextureRect.new()
	heading_icon.custom_minimum_size = Vector2(22, 22)
	heading_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heading_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heading_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titlebar.add_child(heading_icon)
	heading = Label.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.clip_text = true
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_theme_font_size_override("font_size", 19)
	titlebar.add_child(heading)
	shelter_modal_button = button(titlebar, "G", toggle_shelter)
	shelter_modal_button.name = "ShelterModalButton"
	shelter_modal_button.tooltip_text = "В убежище / вернуться к месту выхода [G]"
	shelter_modal_button.focus_mode = Control.FOCUS_NONE
	shelter_modal_button.icon = Art.icon("shelter")
	button(titlebar, "× [Esc]", close_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(530, 220)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	modal.hide()
	app.session.events.subscribe(self, _event)
	update_hud()

func button(parent: Node, text: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = text
	item.expand_icon = false
	item.add_theme_constant_override("icon_max_width", 16)
	var method: String = str(action.get_method())
	var roles := {"save_game": "save", "load_game": "save", "close_panel": "back", "new_game": "shelter", "_prepare_rest": "rest"}
	if roles.has(method):
		item.icon = Art.texture(roles[method])
	elif method == "run_command":
		var arguments: Array = action.get_bound_arguments()
		if not arguments.is_empty():
			var kind: String = arguments[0]
			var commands := {"inventory.transfer": "inventory", "inventory.purchase": "coin", "inventory.claim_parcel": "save", "game.quest_track": "quests", "clock.rest": "rest", "game.contact": "residents", "game.consent": "accept", "game.recruit": "residents"}
			item.icon = Art.texture(commands.get(kind, "farm"))
	item.pressed.connect(action)
	parent.add_child(item)
	return item

func line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 495
	body.add_child(label)

func open_panel(id: String) -> void:
	close_radial()
	if pause_token == 0:
		pause_token = app.session.pauses.acquire_pause("ui:" + id)
	panel_id = id
	hud.hide()
	notice.hide()
	modal.show()
	render_panel()

func close_panel() -> void:
	if pause_token != 0:
		app.session.pauses.release_pause(pause_token)
	pause_token = 0
	panel_id = ""
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	modal.hide()
	hud.show()
	notice.show()

func toggle_radial() -> void:
	if radial.visible:
		close_radial()
	elif panel_id.is_empty() and app.running():
		radial_pause_token = app.session.pauses.acquire_pause("ui:radial")
		radial.reveal(hud.items)

func close_radial() -> void:
	if radial_pause_token != 0:
		app.session.pauses.release_pause(radial_pause_token)
		radial_pause_token = 0
	radial.hide()

func open_quick_slot(index: int) -> void:
	if index >= hud.items.size():
		return
	inventory_container = "player"
	inventory_selection = hud.items[index].instance_id if index >= 0 else ""
	open_panel("inventory")

# Release only UI-owned pause tokens; CoreSession still protects recovery and
# failed durable transitions without partial changes to the world.
func toggle_shelter() -> void:
	var previous_panel: String = panel_id
	var previous_radial: bool = radial.visible
	if previous_radial:
		close_radial()
	if not previous_panel.is_empty():
		close_panel()
	var result: Dictionary = app.toggle_shelter()
	if not result.get("ok", false):
		if not previous_panel.is_empty():
			open_panel(previous_panel)
		elif previous_radial and app.running():
			toggle_radial()
		show_result(result)
	update_hud()

func run_command(kind: String, payload: Dictionary = {}) -> void:
	# Release only this panel's token for the synchronous transaction; unrelated
	# menu/recovery tokens remain active. No simulation frame runs in this gap.
	var previous: String = panel_id
	if pause_token != 0:
		app.session.pauses.release_pause(pause_token)
	pause_token = 0
	app.command(kind, payload)
	if not previous.is_empty():
		pause_token = app.session.pauses.acquire_pause("ui:" + previous)
		schedule_refresh()

func show_result(result: Dictionary) -> void:
	var code: String = result.get("code", "UNAVAILABLE")
	notice.text = ERRORS.get(code, "Ошибка: " + code)
	notice.modulate = Color("b6e5ca") if result.get("ok", false) else Color("f2b39f")
	if app.session.requires_recovery():
		if panel_id == "save":
			schedule_refresh()
		else:
			# Panel commands finish restoring their own pause before switching views.
			call_deferred("_open_recovery_panel")
	update_hud()

func _open_recovery_panel() -> void:
	if app.session.requires_recovery() and panel_id != "save":
		open_panel("save")

func update_hud() -> void:
	if hud == null:
		return
	var state: Dictionary = app.snapshot(false)
	var minute: int = int(state.game_time_minutes)
	var world = app.scene_router.current_world()
	var title: String = world.location_label if is_instance_valid(world) and not world.location_label.is_empty() else NAMES.get(state.scene.current_scene_id, state.scene.current_scene_id)
	var place := title + "  /  День %d · %02d:%02d" % [minute / 1440 + 1, (minute / 60) % 24, minute % 60]
	var items: Array[Dictionary] = []
	var catalog: Dictionary = app.rules().items
	for item in state.inventory.items:
		if item.container_id == "player":
			items.append({
				"instance_id": item.instance_id, "quantity": item.quantity,
				"label": catalog[item.type_id].name + (" [в руках]" if item.instance_id == state.player.get("equipped_weapon_instance_id", "") else ""),
				"icon": ITEM_ICONS.get(item.type_id, Art.texture("inventory")),
			})
	var objective := "Нет отслеживаемых заданий"
	var next_exit := ""
	var order: Dictionary = state.quests.get("expedition", {})
	if not order.is_empty() and not order.claimed:
		objective = "Поручение разведчиков"
		if not order.target.is_empty():
			next_exit = _expedition_exit(state, order.target)
	else:
		for index in range(state.quests.records.size()):
			if state.quests.records[index].status == "active":
				objective = QUEST_TITLES[index]
				break
	hud.update_state(state, items, place, objective, next_exit)
	var returning: bool = state.scene.current_scene_id == "shelter"
	if is_instance_valid(shelter_nav_button):
		shelter_nav_button.text = "Назад · День %d [G]" % (minute / 1440 + 1) if returning else "Убежище [G]"
		shelter_nav_button.tooltip_text = "Вернуться к месту выхода [G]" if returning else "Войти в убежище [G]"
	if is_instance_valid(shelter_modal_button):
		shelter_modal_button.tooltip_text = "Вернуться к месту выхода [G]" if returning else "Войти в убежище [G]"

func _expedition_exit(state: Dictionary, target: String) -> String:
	var manifest: Dictionary = state.world_states.layout
	var here: String = state.scene.current_scene_id
	var key := [manifest.seed, manifest.generator_version, here, target]
	if key != _expedition_route_key:
		_expedition_route_key = key
		var route := Layout.route(Layout.from_manifest(manifest), here, target)
		_expedition_next_exit = route[1] if route.size() > 1 else ""
	return _expedition_next_exit

func _event(_fact: Dictionary) -> void:
	update_hud()
	schedule_refresh()

func schedule_refresh() -> void:
	if not _refresh_pending:
		_refresh_pending = true
		call_deferred("_refresh")

func _refresh() -> void:
	_refresh_pending = false
	if not panel_id.is_empty():
		render_panel()

func render_panel() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	heading.text = PANELS.get(panel_id, panel_id)
	heading_icon.texture = Art.icon(panel_id)
	heading_icon.visible = heading_icon.texture != null
	var state: Dictionary = app.snapshot(false)
	match panel_id:
		"welcome":
			line("Офлайн-песочница · процедурный город")
			line("Убежище доступно сразу: G переносит туда из любого района, даже до первого боя. Повторная G возвращает к месту выхода. Победите врага в больнице для получения Системы.")
			line("WASD/стрелки — движение; мышь — направление удара; ЛКМ — атака; Space — уклонение; E — взаимодействие; G — убежище всегда. Левый Ctrl — быстрое меню рюкзака; 1–4 — открыть предмет в рюкзаке.")
			var has_primary := FileAccess.file_exists(app.save_location)
			var has_backup := FileAccess.file_exists(app.save_location + ".bak")
			if has_primary or has_backup:
				if has_primary:
					button(body, "Продолжить сохранённую игру", app.load_game)
				if has_backup:
					button(body, "Восстановить резервную копию", app.load_game.bind(true))
				button(body, "Новая игра…", open_panel.bind("new_confirm"))
			else:
				render_seed_entry("Начать игру")
		"new_confirm":
			line("Текущий слот будет начат заново. Предыдущие файлы сохранятся как архивные копии.")
			render_seed_entry("Подтвердить новую игру")
			button(body, "Назад", open_panel.bind("menu"))
		"menu":
			line("Симуляция и бой приостановлены. Закрытие меню не снимает паузу восстановления.")
			button(body, "Продолжить", close_panel)
			button(body, "Карта города", open_panel.bind("map"))
			button(body, "Журнал находок", open_panel.bind("journal"))
			button(body, "Системный магазин", open_panel.bind("shop"))
			button(body, "Сохранение / загрузка", open_panel.bind("save"))
			button(body, "Новая игра…", open_panel.bind("new_confirm"))
			button(body, "Об игре и авторах", open_panel.bind("credits"))
			button(body, "Выйти (несохранённое время будет потеряно)", func(): app.get_tree().quit())
		"map":
			if state.schema_version != 4:
				line("В этом сохранении используются исходные локации.")
			else:
				var seed_value: int = int(state.world_states.layout.seed)
				var nodes := Layout.from_manifest(state.world_states.layout)
				var here: String = state.scene.current_scene_id
				line("Мир %d · %s" % [seed_value, nodes[here].label])
				var schematic := Control.new()
				schematic.custom_minimum_size = Vector2(480, 126)
				body.add_child(schematic)
				schematic.draw.connect(draw_city_map.bind(schematic, state))
				if nodes[here].has("exits"):
					line("План локации · вы отмечены золотым, переходы — бирюзовым")
					var local_map := Control.new()
					local_map.custom_minimum_size = Vector2(480, 134)
					body.add_child(local_map)
					local_map.draw.connect(draw_local_map.bind(local_map, nodes[here], app.hero.position))
				var arrival: String = state.scene.entry_point_id
				line("Выходы")
				for id in nodes[here].links:
					line(("↩ " if arrival == "from_" + id else "• ") + nodes[id].label)
				if here == "shelter":
					line("G — вернуться в «%s»" % nodes[state.scene.return_scene_id].label)
				var expedition: Dictionary = state.quests.get("expedition", {})
				if not expedition.is_empty() and not expedition.claimed and not expedition.target.is_empty():
					var route: Array[String] = Layout.route(nodes, here, expedition.target)
					var stops: Array[String] = []
					for id in route:
						stops.append(nodes[id].label)
					line("Маршрут разведки · " + " → ".join(stops))
				line("Посещённые места")
				for id in nodes:
					if id == here or state.scene.positions.has(id):
						line(("● " if id == here else "• ") + nodes[id].label)
			button(body, "Назад", open_panel.bind("menu"))
		"journal":
			line("Известные предметы")
			if state.shelter.discovered_item_type_ids.is_empty():
				line("Журнал пока пуст.")
			for id in state.shelter.discovered_item_type_ids:
				line("• " + app.rules().items[id].name)
			if state.schema_version == 4:
				var nodes := Layout.from_manifest(state.world_states.layout)
				for id in state.world_states.locations:
					var fact: Dictionary = state.world_states.locations[id]
					if fact.get("looted", false) or fact.get("cache_looted", false):
						line("Тайник осмотрен · " + nodes[id].label)
					if fact.get("defeated", false):
						line("Угроза устранена · " + nodes[id].label)
				for id in state.world_states.get("cleared_patrols", []):
					line("Патруль устранён · " + nodes[id].label)
				for id in state.world_states.get("district_events", {}):
					var helped: bool = state.world_states.district_events[id] == "helped"
					line(("Выжившим оказана помощь · " if helped else "В помощи отказано · ") + nodes[id].label)
			button(body, "Назад", open_panel.bind("menu"))
		"credits":
			line("Моё пространственное убежище · игровой прототип")
			if Art.texture("button_frame") != null:
				line("Иконки и оформление интерфейса: Kibyra — Free Medieval Fantasy UI Pack.")
				line("kibyra.itch.io/free-medieval-fantasy-ui-pack")
			line("Движок: Godot. Сведения о лицензиях движка и использованных материалов входят в комплект игры.")
			button(body, "Назад", open_panel.bind("menu"))
		"save":
			var recovering: bool = app.session.requires_recovery()
			if recovering:
				line("Игра приостановлена. Загрузите основной файл, чтобы восстановить последнее записанное состояние. Если файл повреждён, выберите резервную копию.")
				var code: String = app.last_result.get("code", "")
				if code in ["INVALID_STATE", "SAVE_FAILED"]:
					line(ERRORS[code])
			else:
				line("Сохранение включает позиции, здоровье героя, часы, грядки, ресурсы, жителей и квитанции действий.")
				button(body, "Сохранить сейчас", app.save_game)
			button(body, "Загрузить основной файл", app.load_game)
			button(body, "Восстановить резервную копию", app.load_game.bind(true))
			if recovering:
				return
			if state.schema_version == 3:
				line("Перенос сохраняет прогресс. Если старая точка занята новой стеной, герой появится у безопасного входа.")
				button(body, "Перенести сохранение в процедурный город", run_command.bind("session.upgrade_world"))
			elif state.schema_version == 4 and state.world_states.layout.generator_version < Layout.VERSION:
				line("Расширить текущий мир с сохранением прогресса. Если старая точка перекрыта, герой появится у безопасного входа.")
				var label := "Перейти на большие карты" if int(state.world_states.layout.generator_version) < 3 else "Обновить планировки зданий"
				button(body, label, run_command.bind("session.upgrade_world"))
			if app.hero.defeated:
				button(body, "Повторить безопасное восстановление героя", _retry_defeat)
		"inventory":
			render_inventory(state)
		"workshop":
			if state.schema_version != 4 or state.scene.current_scene_id != "shelter":
				line("Мастерская доступна на стройплощадке убежища.")
			else:
				render_workshop(state)
		"farm":
			line("Посадите семена и полейте. Вода в убежище доступна. Рост идёт естественно или во время отдыха.")
			for plot in state.crops.plots:
				line("Грядка %s — %s" % [plot.id.get_slice("_", 1), STATUS[plot.status]])
				var actions := {"empty": ["Посадить (1 семя)", "game.plant"], "planted": ["Полить", "game.water"], "ripe": ["Собрать урожай", "game.harvest"], "spoiled": ["Очистить", "game.clear"]}
				if actions.has(plot.status):
					button(body, actions[plot.status][0], run_command.bind(actions[plot.status][1], {"plot_id": plot.id}))
				if plot.status == "growing":
					line("До зрелости: %d мин. До порчи: %d мин." % [plot.ripe_at - state.game_time_minutes, plot.spoil_at - state.game_time_minutes])
			if state.schema_version == 4 and state.crops.plots.size() == 2:
				button(body, "Построить третью грядку (%d монет)" % app.rules().farm_expansion_cost, run_command.bind("game.expand_farm"))
			button(body, "План отдыха", open_panel.bind("rest"))
		"rest":
			line("Отдых доступен только в убежище. Перед подтверждением показаны срок и риск порчи.")
			button(body, "Рассчитать до ближайшего урожая / на 60 минут", _prepare_rest.bind(app.next_harvest_minute()))
			button(body, "Рассчитать отдых на 6 часов", _prepare_rest.bind(int(state.game_time_minutes) + 360))
			if rest_target > state.game_time_minutes:
				var preview: Dictionary = app.preview_rest(rest_target)
				if preview.ok:
					line("Конечная минута: %d. Испорченных грядок: %d." % [preview.data.actual_to_minute, preview.data.spoiled_plots])
					button(body, "Подтвердить отдых", run_command.bind("clock.rest", {"target_minute": rest_target}))
		"jobs":
			render_jobs(state)
		"district_event":
			var id: String = state.scene.current_scene_id
			if DistrictEvents.available(state, id):
				var event := DistrictEvents.event_for(state, id)
				line(event.title)
				line(event.description)
				button(body, "Помочь", run_command.bind("game.resolve_district", {"choice": "helped"}))
				button(body, "Отказаться", run_command.bind("game.resolve_district", {"choice": "declined"}))
			else:
				line("Встреча завершилась.")
		"camp":
			render_camp(state)
		"residents":
			if state.schema_version == 4 and state.scene.current_scene_id == "louvre":
				button(body, "Объявления и торговля", open_panel.bind("camp"))
			line("Путники присоединяются добровольно. Для каждого нужен запас: %d ед. еды. Резерв нельзя расходовать повторно." % app.rules().food.units_per_resident)
			for resident in state.residents.records:
				line("%s: %s" % ["Путник 1" if resident.id == "resident_1" else "Путник 2", STATUS[resident.status]])
				if resident.status == "unknown":
					button(body, "Познакомиться", run_command.bind("game.contact", {"resident_id": resident.id}))
				elif resident.status != "joined":
					if not resident.consent:
						line("«Я готов поселиться при наличии еды. Решение остаётся за мной.»")
						button(body, "Предложить добровольное соглашение", run_command.bind("game.consent", {"resident_id": resident.id, "accept": true}))
						button(body, "Отказ от соглашения", run_command.bind("game.consent", {"resident_id": resident.id, "accept": false}))
					else:
						button(body, "Выделить еду и заселить", run_command.bind("game.recruit", {"resident_id": resident.id}))
		"quests":
			line("Q03–Q07 — необязательные подсказки. Хозяйство и вылазки работают без отслеживания.")
			for i in range(state.quests.records.size()):
				var quest: Dictionary = state.quests.records[i]
				line("%s · %s — %s" % [quest.id, QUEST_TITLES[i], STATUS[quest.status]])
				if i >= 2 and quest.status != "completed":
					button(body, "Отслеживать / скрыть", run_command.bind("game.quest_track", {"quest_id": quest.id}))
		"shop":
			var catalog: Dictionary = app.rules()
			line(shop_hint(catalog, "seed"))
			if catalog.offers.has("seed"):
				button(body, "Купить: " + offer_description(catalog, "seed"), run_command.bind("inventory.purchase", {"offer_id": "seed"}))
	if panel_id != "inventory" and not notice.text.is_empty():
		line(notice.text)

func render_inventory(state: Dictionary) -> void:
	var names := {"player": "Рюкзак", "storage": "Хранилище"}
	var stacks: Array = state.inventory.items.filter(func(item): return item.container_id == inventory_container)
	var used := 0
	var capacity := 0
	for container in state.inventory.containers:
		if container.id == inventory_container:
			capacity = int(container.capacity_units)
	var selected := {}
	for item in stacks:
		used += int(item.quantity)
		if item.instance_id == inventory_selection:
			selected = item
	if selected.is_empty() and not stacks.is_empty():
		selected = stacks[0]
	inventory_selection = selected.get("instance_id", "")
	var tabs := HBoxContainer.new()
	body.add_child(tabs)
	var accent := Color("b9945a") if state.scene.current_scene_id == "shelter" else Color("bd744d")
	for id in names:
		var tab := button(tabs, names[id], select_inventory.bind(id, ""))
		if id == inventory_container:
			tab.name = "InventoryCurrentTab"
			tab.add_theme_stylebox_override("normal", inventory_style(Color("472a23"), accent, 2))
	var usage := Label.new()
	usage.text = "%d / %d ед.    ·    Монеты %d" % [used, capacity, state.wallet.system_coins]
	usage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	usage.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tabs.add_child(usage)

	if not notice.text.is_empty():
		var feedback := Label.new()
		feedback.text = notice.text
		feedback.modulate = notice.modulate
		feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		feedback.add_theme_font_size_override("font_size", 11)
		body.add_child(feedback)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	body.add_child(content)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	content.add_child(grid)
	var rules: Dictionary = app.rules()
	for index in range(maxi(18, ceili(stacks.size() / 6.0) * 6)):
		var item: Dictionary = stacks[index] if index < stacks.size() else {}
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(47, 35)
		slot.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_theme_constant_override("icon_max_width", 23)
		slot.add_theme_stylebox_override("normal", inventory_style(Color("211e1b"), Color("73523d")))
		slot.add_theme_stylebox_override("disabled", inventory_style(Color("161516"), Color("443831")))
		slot.add_theme_stylebox_override("hover", inventory_style(Color("382820"), accent))
		slot.add_theme_stylebox_override("pressed", inventory_style(Color("503126"), accent, 2))
		slot.add_theme_stylebox_override("focus", inventory_style(Color.TRANSPARENT, Color("f1c27a"), 2))
		grid.add_child(slot)
		if item.is_empty():
			slot.disabled = true
			continue
		slot.icon = ITEM_ICONS.get(item.type_id, Art.texture("inventory"))
		slot.tooltip_text = rules.items[item.type_id].name
		slot.pressed.connect(select_inventory.bind(inventory_container, item.instance_id))
		if item.instance_id == inventory_selection:
			slot.name = "InventorySelectedSlot"
			slot.add_theme_stylebox_override("normal", inventory_style(Color("382820"), accent, 2))
		var count := Label.new()
		count.text = str(item.quantity)
		count.add_theme_font_size_override("font_size", 10)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(count)
		count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		count.offset_left = -19
		count.offset_top = -14
		count.offset_right = -3
		count.offset_bottom = -1
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", inventory_style(Color("231e1a"), accent))
	content.add_child(card)
	var details := VBoxContainer.new()
	card.add_child(details)
	var title := Label.new()
	title.text = "Пусто" if selected.is_empty() else rules.items[selected.type_id].name
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_color_override("font_color", Color("f2d6a4"))
	details.add_child(title)
	if selected.is_empty():
		var hint := Label.new()
		hint.text = "Здесь будут найденные или перенесённые предметы."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(hint)
	else:
		var available: int = Gameplay.available(state, selected)
		if inventory_container == "player" and rules.combat.weapons.has(selected.type_id):
			var equipped: bool = state.player.get("equipped_weapon_instance_id", "") == selected.instance_id
			var skill: Dictionary = Combat.profile(state, rules)
			var weapon: Dictionary = rules.combat.weapons[selected.type_id]
			var fighting: Label = Label.new()
			fighting.text = "В руках" if equipped else "Оружие — не экипировано"
			fighting.text += "\nУрон: %d · Дальность: %d" % [int(weapon.damage) + int(skill.experience_bonus), int(weapon.reach)]
			fighting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			details.add_child(fighting)
			button(details, "Снять оружие" if equipped else "Взять в руки", run_command.bind("game.equip_weapon", {"instance_id": "" if equipped else selected.instance_id}))
		var quantities := Label.new()
		quantities.text = "Всего: %d
Свободно: %d
В резерве: %d" % [selected.quantity, available, int(selected.quantity) - available]
		details.add_child(quantities)
		var target := "storage" if inventory_container == "player" else "player"
		var move := button(details, "В " + names[target].to_lower(), run_command.bind("inventory.transfer", {
			"instance_id": selected.instance_id, "from_id": inventory_container, "to_id": target, "quantity": available,
		}))
		move.disabled = available <= 0
	var actions := HBoxContainer.new()
	body.add_child(actions)
	if state.schema_version == 4 and state.scene.current_scene_id == "shelter":
		button(actions, "Работа жителей", open_panel.bind("jobs"))
	if "starter" not in state.shelter.claimed_parcel_ids:
		button(actions, "Стартовая посылка", run_command.bind("inventory.claim_parcel", {"parcel_id": "starter"}))

func select_inventory(container: String, instance_id: String) -> void:
	inventory_container = container
	inventory_selection = instance_id
	render_panel()
	var focus_name := "InventoryCurrentTab" if instance_id.is_empty() else "InventorySelectedSlot"
	var focused := body.find_child(focus_name, true, false) as Button
	if focused != null:
		focused.grab_focus()

static func inventory_style(fill: Color, border: Color, thickness: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(thickness)
	style.set_corner_radius_all(3)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, 6)
	return style

func draw_local_map(canvas: Control, node: Dictionary, hero_position: Vector2) -> void:
	var floor: Rect2 = node.bounds
	var scale_factor := minf((canvas.size.x - 16) / floor.size.x, (canvas.size.y - 12) / floor.size.y)
	var origin := (canvas.size - floor.size * scale_factor) / 2.0 - floor.position * scale_factor
	canvas.draw_rect(Rect2(origin + floor.position * scale_factor, floor.size * scale_factor), Color("273334"))
	for rect in node.get("roadways", node.get("rooms", [])):
		canvas.draw_rect(Rect2(origin + rect.position * scale_factor, rect.size * scale_factor), Color("536060"))
	if node.has("floor_plan"):
		for room in node.floor_plan.rooms.values():
			var rect: Rect2 = room.rect
			var tint := Color("536060") if room.unit.is_empty() else Color("56514d")
			canvas.draw_rect(Rect2(origin + rect.position * scale_factor, rect.size * scale_factor), tint)
		for door in node.floor_plan.doors:
			var point: Vector2 = origin + door.position * scale_factor
			canvas.draw_circle(point, 2, Color("aa9777"))
	for rect in node.obstacles:
		canvas.draw_rect(Rect2(origin + rect.position * scale_factor, rect.size * scale_factor), Color("151b20"))
	for exit in node.exits.values():
		var point: Vector2 = origin + exit.position * scale_factor
		canvas.draw_rect(Rect2(point - Vector2(3, 3), Vector2(6, 6)), Color("86cfb0"))
	canvas.draw_circle(origin + hero_position * scale_factor, 4, Color("edbb6d"))

func draw_city_map(canvas: Control, state: Dictionary) -> void:
	var manifest: Dictionary = state.world_states.layout
	var version: int = int(manifest.generator_version)
	var roads := Layout.roads(int(manifest.seed), version)
	var order := [0, 1, 3, 2]
	if version != 1:
		order = [roads[0][0], roads[0][1], roads[1][1], roads[2][1]]
	var positions := {}
	var corners := [Vector2(67, 27), Vector2(398, 27), Vector2(398, 88), Vector2(67, 88)]
	var visible_districts := {}
	var here: String = state.scene.current_scene_id
	var active := int(here.get_slice("_", 1))
	for index in range(order.size()):
		var id := Layout.street(order[index])
		positions[order[index]] = corners[index]
		visible_districts[order[index]] = order[index] == active or state.scene.positions.has(id)
	canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(canvas.size.x, 121)), Color("1c292f"))
	for edge in roads:
		if visible_districts[edge[0]] or visible_districts[edge[1]]:
			canvas.draw_line(positions[edge[0]], positions[edge[1]], Color("64887f"), 3)
	for district in order:
		var center: Vector2 = positions[district]
		var tint := Color("d1ae70") if district == active else Color("7ca99b") if visible_districts[district] else Color("4d6264")
		canvas.draw_circle(center, 10, tint)
		var caption := "Район %d" % (district + 1) if visible_districts[district] else "?"
		canvas.draw_string(ThemeDB.fallback_font, center + Vector2(-24, 24), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tint)

func render_seed_entry(button_text: String) -> void:
	line("Начальное число мира от 0 до 2147483647. Пустое поле создаёт случайный мир.")
	var seed_input := LineEdit.new()
	seed_input.placeholder_text = "Случайный мир"
	body.add_child(seed_input)
	seed_input.text_submitted.connect(app.new_game)
	button(body, button_text, func(): app.new_game(seed_input.text))

func render_camp(state: Dictionary) -> void:
	if state.schema_version != 4 or state.scene.current_scene_id != "louvre":
		line("Доска объявлений находится на стоянке.")
		return
	var offer := Camp.schedule(int(state.game_time_minutes), int(state.world_states.layout.seed))
	var network: Dictionary = state.world_states.get("camp_network", Camp.empty_state())
	if offer.active and network.last_contract_day != offer.day:
		var faction: Dictionary = Camp.FACTIONS[offer.faction]
		var item: String = app.rules().items[faction.request].name
		line("%s просят %s ×%d до 18:00. Награда — %d монет и доверие." % [faction.name, item.to_lower(), faction.quantity, faction.reward])
		button(body, "Передать припасы", run_command.bind("game.fulfill_contract", {"day": offer.day, "faction": offer.faction}))
	elif network.last_contract_day == offer.day:
		line("Сегодняшняя просьба выполнена.")
	else:
		line("Просьбы принимают с 06:00 до 18:00.")
	for id in Camp.FACTIONS:
		var faction: Dictionary = Camp.FACTIONS[id]
		var reputation: int = network.reputation.get(id, 0)
		line("%s · доверие %d" % [faction.name, reputation])
		if reputation > 0 and network.last_trade.get(id, -1) != offer.day:
			var item: String = app.rules().items[faction.goods].name
			button(body, "Купить %s ×%d за %d монет" % [item.to_lower(), faction.goods_quantity, faction.price], run_command.bind("game.trade_camp", {"faction": id}))
	var expedition: Dictionary = state.quests.get("expedition", {})
	if expedition.is_empty():
		button(body, "Взять поручение разведчиков", run_command.bind("game.accept_expedition"))
	elif not expedition.claimed:
		if expedition.target.is_empty():
			line("Все больницы разведаны. Стоянке нужен утиль ×%d." % Expedition.SUPPLY_COST)
		else:
			var nodes := Layout.from_manifest(state.world_states.layout)
			line("Поручение · устранить угрозу · " + nodes[expedition.target].label)
		button(body, "Сдать поручение · %d монет" % Expedition.REWARD, run_command.bind("game.claim_expedition"))
	else:
		line("Поручение разведчиков закрыто.")
	button(body, "К путникам", open_panel.bind("residents"))

static func work_ration_hint(rules: Dictionary) -> String:
	var food_names := PackedStringArray()
	var items: Dictionary = rules.get("items", {})
	var food: Dictionary = rules.get("food", {})
	for type_id in food.get("accepted_food_type_ids", []):
		var definition: Dictionary = items.get(type_id, {})
		if definition.get("edible") == true and definition.get("name") is String:
			food_names.append(definition.name)
	return "Смена требует %d ед. свободной еды (%s). Кровать сокращает смену со %d до %d мин." % [
		Work.FOOD_UNITS_PER_SHIFT, ", ".join(food_names), Work.DURATION, Work.RESTED_DURATION]

func render_jobs(state: Dictionary) -> void:
	if state.schema_version != 4 or state.scene.current_scene_id != "shelter":
		line("Назначить работу можно в убежище.")
		return
	var rules: Dictionary = app.rules()
	line(work_ration_hint(rules))
	for resident in state.residents.records:
		if resident.status != "joined":
			continue
		line("Путник %s · смена %d мин." % [resident.id.get_slice("_", 1), Work.duration(state, resident.id)])
		var shift: Dictionary = resident.get("shift", {})
		if shift.is_empty():
			for id in Work.JOBS:
				var job: Dictionary = Work.JOBS[id]
				button(body, "%s · %s ×%d" % [job.label, rules.items[job.output].name, job.quantity], run_command.bind("game.assign_shift", {"resident_id": resident.id, "job": id}))
		elif shift.ready:
			button(body, "Забрать результат", run_command.bind("game.collect_shift", {"resident_id": resident.id}))
		else:
			line("%s · осталось %d мин." % [Work.JOBS[shift.job].label, shift.due - state.game_time_minutes])

func render_workshop(state: Dictionary) -> void:
	line("Шкаф добавляет %d мест в хранилище. Кровать сокращает смену жильца." % Construction.CABINET_CAPACITY)
	button(body, "Работа жителей", open_panel.bind("jobs"))
	var buildings: Dictionary = state.shelter.get("buildings", {})
	var grid := GridContainer.new()
	grid.columns = Construction.COLUMNS
	body.add_child(grid)
	for index in range(Construction.COLUMNS * Construction.ROWS):
		var cell := str(index)
		var label: String = Construction.STRUCTURES[buildings[cell]].label if buildings.has(cell) else "·"
		var tile := button(grid, "%d  %s" % [index + 1, label], select_building_cell.bind(cell))
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.disabled = cell == building_cell
	line("Клетка %d" % (int(building_cell) + 1))
	if buildings.has(building_cell):
		button(body, "Разобрать без возврата материалов", run_command.bind("game.dismantle", {"cell": building_cell}))
	else:
		for id in Construction.STRUCTURES:
			var spec: Dictionary = Construction.STRUCTURES[id]
			var item: String = app.rules().items[spec.item].name
			button(body, "Построить %s · %s ×%d" % [spec.label.to_lower(), item, spec.cost], run_command.bind("game.build", {"cell": building_cell, "structure": id}))
	if "bench" in buildings.values():
		for id in Construction.RECIPES:
			var recipe: Dictionary = Construction.RECIPES[id]
			button(body, "Изготовить %s · %s ×%d" % [recipe.label.to_lower(), app.rules().items[recipe.input].name, recipe.cost], run_command.bind("game.craft", {"recipe": id}))
	else:
		line("Верстак открывает ремесло. Утиль можно найти на улицах города.")

func select_building_cell(cell: String) -> void:
	building_cell = cell
	schedule_refresh()

func _prepare_rest(target: int) -> void:
	rest_target = target
	render_panel()

func _retry_defeat() -> void:
	close_panel()
	app.player_defeated()

func _exit_tree() -> void:
	if app != null and app.session != null:
		app.session.events.unsubscribe_owner(self)
		if radial_pause_token != 0:
			app.session.pauses.release_pause(radial_pause_token)
		if pause_token != 0:
			app.session.pauses.release_pause(pause_token)

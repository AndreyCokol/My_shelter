extends Control

var app
var panel_id: String = ""
var pause_token: int = 0
var hud: Label
var location: Label
var notice: Label
var modal: ColorRect
var body: VBoxContainer
var heading: Label
var rest_target: int = 0
var _refresh_pending: bool = false
const NAMES = {"hospital": "Больница", "outside": "Город", "shelter": "Убежище", "louvre": "Стоянка"}
const PANELS = {"welcome": "Моё пространственное убежище", "menu": "Пауза", "inventory": "Рюкзак и хранилище", "farm": "Грядки", "rest": "Безопасный отдых", "residents": "Путники", "quests": "Задания", "shop": "Системный магазин", "save": "Сохранение и восстановление", "new_confirm": "Начать заново?"}
const STATUS = {"empty": "пусто", "planted": "нужен полив", "growing": "растёт", "ripe": "созрело", "spoiled": "испортилось", "unknown": "не знакомы", "contacted": "готов поговорить", "declined": "отказ", "AWAITING_SUPPLIES": "согласие есть, нужны припасы", "joined": "поселился", "inactive": "не отслеживается", "active": "в работе", "completed": "выполнено"}
const ERRORS = {"OK": "Готово", "ALREADY_APPLIED": "Действие уже выполнено", "UNAVAILABLE": "Сейчас недоступно. Проверьте условия или восстановите сохранение.", "INVALID_STATE": "Состояние изменилось: обновите действие или выберите резервную копию.", "INVALID_ARGUMENT": "Проверьте параметры действия.", "INSUFFICIENT_RESOURCES": "Не хватает доступных ресурсов. Зарезервированная еда не расходуется.", "CAPACITY_EXCEEDED": "Рюкзак заполнен. Перенесите предметы в хранилище.", "REQUIRES_CONSENT": "Сначала нужно добровольное согласие путника.", "STALE_REVISION": "Данные изменились. Экран обновлён — повторите выбор.", "NOT_IN_SAFE_AREA": "Отдых и работа с грядками доступны в убежище.", "SAVE_FAILED": "Не удалось записать сохранение. Действие не подтверждено.", "PAUSED": "Осталась другая причина паузы. Закройте её прежде, чем действовать.", "NOT_FOUND": "Объект не найден."}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 13
	var style := StyleBoxFlat.new()
	style.bg_color = Color("203134")
	style.border_color = Color("537773")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	theme.set_stylebox("normal", "Button", style)
	var hover := style.duplicate()
	hover.bg_color = Color("365650")
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", hover)
	self.theme = theme
	var top := Panel.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 80
	add_child(top)
	var topstyle := StyleBoxFlat.new()
	topstyle.bg_color = Color("142329")
	top.add_theme_stylebox_override("panel", topstyle)
	location = Label.new()
	location.position = Vector2(15, 6)
	location.add_theme_font_size_override("font_size", 17)
	top.add_child(location)
	hud = Label.new()
	hud.position = Vector2(15, 31)
	top.add_child(hud)
	var nav := HBoxContainer.new()
	nav.position = Vector2(15, 53)
	top.add_child(nav)
	for entry in [["Рюкзак [I]", "inventory"], ["Задания [Tab]", "quests"], ["Магазин", "shop"], ["Меню [Esc]", "menu"]]:
		var nav_button := button(nav, entry[0], open_panel.bind(entry[1]))
		nav_button.focus_mode = Control.FOCUS_NONE
	notice = Label.new()
	notice.position = Vector2(15, 345)
	notice.size = Vector2(610, 15)
	notice.clip_text = true
	notice.add_theme_font_size_override("font_size", 11)
	notice.text = "WASD — движение · ЛКМ — удар · Space — уклонение · E — рядом с объектом"
	add_child(notice)
	modal = ColorRect.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.color = Color(0.02, 0.06, 0.08, 0.85)
	add_child(modal)
	var panel := PanelContainer.new()
	panel.position = Vector2(35, 42)
	panel.size = Vector2(570, 290)
	var panelstyle := StyleBoxFlat.new()
	panelstyle.bg_color = Color("182a30")
	panelstyle.border_color = Color("73998b")
	panelstyle.set_border_width_all(1)
	panelstyle.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panelstyle)
	modal.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	var titlebar := HBoxContainer.new()
	box.add_child(titlebar)
	heading = Label.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 19)
	titlebar.add_child(heading)
	button(titlebar, "Закрыть [Esc]", close_panel)
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
	if pause_token == 0:
		pause_token = app.session.pauses.acquire_pause("ui:" + id)
	panel_id = id
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
	update_hud()

func update_hud() -> void:
	if hud == null:
		return
	var state: Dictionary = app.snapshot()
	var minute: int = int(state.game_time_minutes)
	location.text = NAMES[state.scene.current_scene_id] + "  /  День %d · %02d:%02d" % [minute / 1440 + 1, (minute / 60) % 24, minute % 60]
	hud.text = "Здоровье %d  ·  Монеты %d  ·  Опыт героя %d  ·  Опыт убежища %d" % [app.hero.health, state.wallet.system_coins, state.player.xp, state.shelter.xp]

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
	var state: Dictionary = app.snapshot()
	match panel_id:
		"welcome":
			line("Офлайн-песочница · первый игровой прототип")
			line("Победите противника в больнице. Откройте убежище, вырастите урожай и помогите двум путникам обустроиться. После обучения игра свободная.")
			line("WASD/стрелки — движение; мышь — направление удара; ЛКМ — атака; Space — уклонение; E — взаимодействие; G — убежище после открытия.")
			if FileAccess.file_exists(app.save_location):
				button(body, "Продолжить сохранённую игру", app.load_game)
				button(body, "Новая игра…", open_panel.bind("new_confirm"))
			else:
				button(body, "Начать игру", app.new_game)
		"new_confirm":
			line("Текущий слот будет начат заново. Предыдущие файлы сохранятся как архивные копии.")
			button(body, "Подтвердить новую игру", app.new_game)
			button(body, "Назад", open_panel.bind("menu"))
		"menu":
			line("Симуляция и бой приостановлены. Закрытие меню не снимает паузу восстановления.")
			button(body, "Продолжить", close_panel)
			button(body, "Сохранение / загрузка", open_panel.bind("save"))
			button(body, "Новая игра…", open_panel.bind("new_confirm"))
			button(body, "Выйти (несохранённое время будет потеряно)", func(): app.get_tree().quit())
		"save":
			line("Сохранение включает позиции, здоровье героя, часы, грядки, ресурсы, жителей и квитанции действий.")
			button(body, "Сохранить сейчас", app.save_game)
			button(body, "Загрузить основной файл", app.load_game)
			button(body, "Восстановить резервную копию", app.load_game.bind(true))
			if app.hero.defeated:
				button(body, "Повторить безопасное восстановление героя", _retry_defeat)
		"inventory":
			line("Системная посылка доступна после открытия убежища. Переносится весь свободный остаток стека.")
			button(body, "Получить стартовую посылку", run_command.bind("inventory.claim_parcel", {"parcel_id": "starter"}))
			for item in state.inventory.items:
				var available: int = preload("res://game/systems/gameplay/gameplay_commands.gd").available(state, item)
				line("%s ×%d · %s · свободно %d" % [app.rules().items[item.type_id].name, item.quantity, "рюкзак" if item.container_id == "player" else "хранилище", available])
				if available > 0:
					button(body, "В хранилище" if item.container_id == "player" else "В рюкзак", run_command.bind("inventory.transfer", {"instance_id": item.instance_id, "from_id": item.container_id, "to_id": "storage" if item.container_id == "player" else "player", "quantity": available}))
		"farm":
			line("Посадите семена и полейте. Вода в убежище доступна. Рост идёт естественно или во время отдыха.")
			for plot in state.crops.plots:
				line("%s — %s" % ["Грядка 1" if plot.id == "plot_1" else "Грядка 2", STATUS[plot.status]])
				var actions := {"empty": ["Посадить (1 семя)", "game.plant"], "planted": ["Полить", "game.water"], "ripe": ["Собрать урожай", "game.harvest"], "spoiled": ["Очистить", "game.clear"]}
				if actions.has(plot.status):
					button(body, actions[plot.status][0], run_command.bind(actions[plot.status][1], {"plot_id": plot.id}))
				if plot.status == "growing":
					line("До зрелости: %d мин. До порчи: %d мин." % [plot.ripe_at - state.game_time_minutes, plot.spoil_at - state.game_time_minutes])
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
		"residents":
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
			var titles := ["Победить противника", "Открыть убежище", "Посадить семена", "Собрать урожай", "Найти путников", "Получить согласие", "Заселить двух жителей"]
			line("Q03–Q07 — необязательные подсказки. Хозяйство и вылазки работают без отслеживания.")
			for i in range(state.quests.records.size()):
				var quest: Dictionary = state.quests.records[i]
				line("%s · %s — %s" % [quest.id, titles[i], STATUS[quest.status]])
				if i >= 2 and quest.status != "completed":
					button(body, "Отслеживать / скрыть", run_command.bind("game.quest_track", {"quest_id": quest.id}))
		"shop":
			line("2 семени — 3 монеты. Если монеты закончились, семена можно найти в городе: запасы возобновляются через час игрового времени.")
			button(body, "Купить семена", run_command.bind("inventory.purchase", {"offer_id": "seed"}))
	if not notice.text.is_empty():
		line(notice.text)

func _prepare_rest(target: int) -> void:
	rest_target = target
	render_panel()

func _retry_defeat() -> void:
	close_panel()
	app.player_defeated()

func _exit_tree() -> void:
	if app != null and app.session != null:
		app.session.events.unsubscribe_owner(self)
		if pause_token != 0:
			app.session.pauses.release_pause(pause_token)

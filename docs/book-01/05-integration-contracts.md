# Контракты интеграции A1–A5 (проектная спецификация, G0)

**Версия контракта:** 0.1-DRAFT. **Владелец:** A1. Только первая книга. Цель — изолированная параллельная разработка без редактирования чужих сцен и скриптов.

Этот документ описывает **предлагаемый интерфейс**, не готовый API. На Gate G0 A1 реализует адаптеры/заглушки, A2–A5 подтверждают использование. После G0 изменение публичной сигнатуры — через PR и уведомление всех затронутых агентов.

## 1. Схема ответственности

| Общие операции | Единственный владелец | Вызовы остальных |
|---|---|---|
| Роутинг сцен, текущая позиция игрока, вход/выход из убежища | A1 | `SceneRouter.request_transition(...)` |
| Игровое время, ускорение/пауза, tick, **безопасный игроковый пропуск до урожая** | A1 | `GameClock.get_hours()`, `try_advance_to(target_hour, context)`, событие `time_advanced` |
| Две прогрессии и обнаруженные виды предметов | A1 | `ProgressionService.apply_*(...)`, событие прогрессии |
| Инвентарь, хранилища, расход монет, одноразовая награда | A1 | `InventoryService.try_transfer(...)`, `RewardService.grant_once(...)` |
| Персонаж, враги, боевые столкновения, физический лут | A2 | Публикация `enemy_defeated`, запросы инвентаря A1 |
| Поля, урожай, картофель, погреб, здания, цены на фермерские объекты, **ожидание у палатки** | A3 | `FarmService`, `BuildingService`, `FarmService.request_wait_for_plot(plot_id)` через A1 часы/инвентарь |
| Принятие контракта, NPC, квестовые флаги, **статус ожидания снабжения** и логику жителей | A4 | `ResidentService`, `QuestService`; квитанция резерва от транзакции A1 |
| HUD, диалоги как визуальное окно, системные панели, art & E2E | A5 | Чтение публичных snapshot/событий; вызов `try_* / request_*`, никакого прямого изменения данных |
| Сохранение/загрузка всех модулей | A1 | Модули A2–A4 реализуют `export_state()/import_state(data)` |

## 2. События (предварительный контракт)

Предлагаемый интерфейс `EventBus.emit_event(event_id: StringName, payload: Dictionary)`. События **уведомляют**; состояние изменяет только система-владелец. Каждое одноразовое действие обрабатывается через сервис с `action_id` для идемпотентности. Ни один слушатель не должен повторно выдавать награду при уведомлении.

| `event_id` | Поля `payload` (минимум) | Производитель | Подписчики |
|---|---|---|---|
| `enemy_defeated` | `enemy_id`, `enemy_type_id`, `is_system_weapon`, `action_id` | A2 | A1 XP/rewards, A4 квесты, A5 HUD |
| `item_transferred` | `item_instance_id`, `item_type_id`, `from_id`, `to_id`, `action_id` | A1 | A1 discovery, A3 storage, A4 квесты |
| `first_item_type_discovered` | `item_type_id`, `shelter_xp_awarded`, `action_id` | A1 | A4, A5 |
| `shelter_entered` | `origin_scene_id`, `destination_scene_id` | A1 | A3, A4, A5 |
| `time_advanced` | `game_hours`, `delta_hours`, `advance_reason` | A1 | A3 рост, A4 поздние таймеры, A5 часы |
| `crop_harvested` | `plot_id`, `item_type_id`, `quantity`, `action_id`, `inventory_transaction_id` | A3 | A4 quests, A5 UI |
| **`arrival_food_reserved`** | `reservation_id`, `item_type_id`, `quantity`, `action_id` | A1 | A4 переселение, A5 UI |
| `resident_recruited` | `resident_id`, `contract_version`, `action_id`, `reservation_id` | A4 | A1 progression, A3 поздние потребности, A5 |
| `quest_completed` | `quest_id`, `action_id` | A4 | A1 rewards, A5 |
| `parcel_claimed` | `parcel_id`, `action_id` | A1 | A3, A4, A5 |
| `game_state_loaded` | `save_version` | A1 | A2–A5 refresh views |

**Первые переселенцы — одна транзакция:** A4 допускает оформление согласия Алис и Пирра до снабжения, затем переводит их в `AWAITING_SUPPLIES`. A4 отправляет A1 команду `InventoryService.try_reserve_arrival_food(action_id, item_type_id, quantity=2)` для **двух единиц выращенной картошки**. A1 атомарно перемещает их в резерв и возвращает неизменяемый `reservation_id`, поддерживает идемпотентный повтор того же `action_id` после сбоя/загрузки. A4 записывает квитанцию и **только затем** завершает заселение, по одному событию на уникального жителя. Без запаса договоры остаются действующими, люди ждут переселения. Это **[П] MVP**, не книжная универсальная норма питания. Регулярное потребление пищи по часам — P1.

**Ожидание урожая в игре:** A3 проверяет посев, воду и `ready_at`, затем из палатки запрашивает у A1 `GameClock.try_advance_to(ready_at, context=shelter_rest)`. A1 подтверждает, что герой в безопасном убежище и период допустим, продвигает **единые** игровые часы, уведомляет модули, A3 вычисляет зрелость по абсолютному времени. Нельзя вызывать QA-only `advance_for_test` из игрового UI. При невозможности ожидания показывается явная ошибка, часы не изменяются.

**Сбор урожая — одна транзакция:** A3 просит A1-InventoryService добавить урожай. Только после успешной транзакции A3 публикует `crop_harvested` с её `inventory_transaction_id`; событие является уведомлением и не добавляет предмет повторно. При неуспешном добавлении событие не публикуется. Аналогично A2 не создаёт лут параллельно награде A1.

## 3. Общий формат ID

- `item_type_id`, `crop_type_id`, `building_type_id`, `enemy_type_id` — **устойчивые** строковые ID из данных.
- `item_instance_id`, `resident_id`, `enemy_id` — уникальные ID экземпляров, сохраняемые между загрузками там, где сущность постоянна.
- `action_id` — уникальное описание **совершённой** операции, сохраняемое вместе с её результатом; повтор операции с тем же ID возвращает уже записанный результат.
- **Никаких имён как ID:** «Алис» и «Сергей» — отображаемый текст, не машинный идентификатор. Для сюжетного NPC — например `npc_alice`, `npc_pirr`.

## 4. Начальные модели (без канонизации игрового баланса)

```text
GameState
  story_flags: Set[StringName]
  current_scene_id: StringName
  last_outside_position: Vector2
  save_version: int

PlayerState
  health, level, xp, stats, unlocked_skills

ShelterState
  area, level, xp, coins, discovered_item_type_ids
  parcels_claimed, placed_buildings, storage_registry
  arrival_food_reservations: Dictionary[action_id -> reservation_id]

CropState
  plot_id, crop_type_id, stage
  planted_at_game_hour, last_watered_at_game_hour, ready_at, spoil_at

ResidentState
  resident_id, dialogue_state, signed_rules_version
  home_id, job_id, food_need, status
  contract_status: NOT_SIGNED | AWAITING_SUPPLIES | RESIDENT
  arrival_food_reservation_id
  # MVP: job_id — только сохранённое назначение; автоматическое выполнение работы/потребление пищи — P1

QuestState
  quest_id, state, objective_progress
  started_at_game_hour, expires_at_game_hour, reward_action_id
```

Точные поля, типы Godot Resources и сериализация **согласуются на G0**. Все значения, которых нет в книге, остаются `game_balance`. QA продвигает игровые часы только тестовой командой общего GameClock; отдельные таймеры фермы/квестов запрещены.

## 5. Инварианты между модулями

1. Только A1 пишет `character_xp` и `shelter_xp`; отдельные `shelter_xp` за впервые обнаруженный `item_type_id` выдаются один раз.
2. **Одна операция — одна выдача** предмета, монет, XP, посылки, жителя, результата задания.
3. Таймеры A3 и A4 считают **игровые часы A1**, а не локальные таймеры UI. Продвижение времени на 72 часа одним действием должно корректно пересчитать стадии растений, таймеры и одноразовые события.
4. Ведро воды, семена, урожай, **первый запас питания для двух жителей** и покупка используют общие транзакции предметов; никакого отрицательного количества.
5. Сюжетный квест не открывает механику повторно, если флаг уже установлен.
6. A2 создаёт визуальный объект врага; A1 начисляет награду по событию, A4 отслеживает убитого для квестов, A5 показывает текст.
7. После загрузки состояние NPC, урожая, предметов и квестов согласовано; UI перерисовывается из данных.

## 6. Сохранения и интеграция

A1 хранит `save_version` и записывает единый файл; каждый владелец модуля предоставляет сериализацию **без NodePath и ссылок на узлы сцен**:

```json
{
  "save_version": 1,
  "game_time": 0,
  "story_flags": [],
  "current_scene": "hospital",
  "player": {},
  "inventory": {},
  "shelter": {},
  "crops": {},
  "residents": {},
  "arrival_food_reservations": {},
  "quests": {},
  "completed_actions": []
}
```

Этот JSON — **образец контракта**, не существующее сохранение и не доказательство канонических стартовых значений.

### CI и test stubs
- На **G1a A1** готовит mock EventBus, GameClock, InventoryService, ProgressionService, SceneRouter и минимальный SaveManager contract, **до** завершения остального ядра. На **G1b A2–A5** работают со стабами независимо; A1 интегрирует малыми PR.
- A1 готовит mock EventBus, GameClock, InventoryService, ProgressionService, SceneRouter. QA-only метод `GameClock.advance_for_test(hours: float)` доступен только тестовому запуску; в релизной сборке его нет. Все игровые таймеры читают один GameClock. Агенты тестируют свои сцены/системы автономно на mock-сервисах.
- Сборка тестируется в Godot headless. Интеграционные сцены с настоящими API собирает A1.
- A5 проверяет E2E-01—05; каждый агент отвечает за unit/integration тесты собственных модулей.
- **Ни один агент не использует чужую сцену как редактируемый шаблон**: подключать через инстанцирование и публичный API.

## 7. Изменения контракта

Если не хватает события / типа / команды: создать Issue `[CONTRACT] Что нужно изменить и зачем`, приложить минимальный пример и связанные FR; A1 принимает, меняет версию, уведомляет заинтересованных и только после этого происходит интеграция. Не создавать параллельные реализации того же API.

**G0 принят** только после согласования scope, открытых технических решений, событий, API и структуры сохранений всеми пятью агентами и явного утверждения владельца проекта, зафиксированного **URL Issue/PR + commit SHA**. Принципы 2 картофелин и обычного ожидания урожая — **кандидаты G0**, не разрешение реализовать их без одобрения. До этого контракт остаётся **DRAFT**, реализация по нему не начинается.

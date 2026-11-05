# 07 — Контракт модулей, операций и сохранений (proposal v1)

**Статус:** 1.0-PROPOSAL / G0 BLOCKED · **Дата:** 2026-11-05. Дополнение-кандидат к [05-integration-contracts.md](05-integration-contracts.md). **Не** заменяет контракт без решения владельца. Сигнатуры ниже — псевдоконтракты GDScript; код ещё не существует.

## 1. Базовые принципы
1. **Команда меняет состояние; событие только сообщает об уже завершённом изменении.** Из UI нельзя писать `campaign_state` напрямую.
2. Команда принимает `action_id`, обязательный `context` (scene/player/initiator) и типизированный payload. Вызовы синхронны на main thread; конкурентные/повторно входящие вызовы сериализует `GameCoordinator`.
3. Команда возвращает **один** `CommandResult`, успех после атомарного commit. По `action_id` сохраняется отпечаток payload и итог. Повтор тех же параметров возвращает записанный исход, разные параметры с тем же `action_id` → `ACTION_CONFLICT`.
4. Границы транзакций не равны границам файлов/агентов. Cross-domain commit делает A1 coordinator: A3/A4 дают валидаторы/планы изменения, A1 проверяет inventory и одновременно коммитит DTO затронутых доменов.
5. EventBus получает уведомления **после** commit, упорядоченно. Модуль может инициировать новую **команду** на основании события только с новым детерминированным `action_id` и проверкой дубликата; для P0 награды/квесты должны фиксироваться в той же основной транзакции, а не зависеть от необязательного listener.
6. Ошибки не оставляют частично изменённых данных; никакой выдачи предмета через animation callback.
7. Данные UI — snapshot/deep copy или immutable DTO, со `state_revision`; UI не хранит авторитетные копии предметов/жителей.

## 2. Стабильные типы (предлагаемые)

```text
ActionId        := String UUID/UUID-like persistent token (не кадровое время)
EntityId        := String, stable within campaign
ItemTypeId      := String, stable catalog key; e.g. "crop.potato"
ItemInstanceId  := String, persistent item/stack instance ID
SceneId         := "hospital" | "paris" | "shelter" | "louvre" [MVP]
GameMinute      := int >= 0
StateRevision   := int monotonically increasing
CommandResult   := {
  ok: bool,
  code: ErrorCode,
  action_id: String,
  state_revision: int,
  data: Dictionary,          # only public receipt/snapshot DTO
  message_key: String        # localization key; not free-form UI text
}
ErrorCode :=
  OK | ALREADY_APPLIED | ACTION_CONFLICT |
  INVALID_ARGUMENT | INVALID_STATE | NOT_FOUND |
  INSUFFICIENT_RESOURCES | CAPACITY_EXCEEDED |
  TRANSFER_FORBIDDEN | REQUIRES_CONSENT |
  NOT_IN_SAFE_AREA | PAUSED | SAVE_FAILED | UNAVAILABLE
DomainEvent := {
  event_id: String,        # unique immutable event occurrence ID
  event_type: StringName,  # e.g. "crop_harvested"
  action_id: String,
  game_minute: int,
  state_revision: int,
  payload: Dictionary
}
```

**Naming:** `event_type` — тип, `event_id` — отдельный уникальный факт. Не переиспользовать `event_id`/uuid как тип; старый `EventBus.emit_event(event_id, payload)` из 05 после G0 уточнить как `publish_after_commit(event: DomainEvent)` (breaking change). Версия изменения должна быть одобрена всеми потребителями.

## 3. Черновые публичные операции и право записи

| Facade / владелец | Команды и запросы | Гарантии |
|---|---|---|
| `GameSession` / A1 | `new_campaign(seed?) -> Result`; `get_snapshot() -> CampaignSnapshot`; `set_pause(bool) -> Result` | Одна кампания; копии состояния; без player data в UI |
| `SceneRouter` / A1 | `try_transition(action_id, destination_scene_id, entry_point_id)` | Пропуск только доступных сцен, save return point, откат при ошибке загрузки |
| `GameClock` / A1 | `get_game_minute()`; `try_rest_until(action_id, target_minute, context)`; `advance_for_test(minutes)` QA-only | Один clock для A3/A4, монотонность, расчёт границ; test API недоступно release |
| `ProgressionService` / A1 | `apply_combat_reward_once(action_id, combat_receipt)`; `register_first_item_type(action_id, item_type_id)` | Только один writer XP и discoveries; возвращается receipt |
| `InventoryService` / A1 | `try_transfer(action_id, item_instance_id, from_id, to_id, quantity)`; `try_spend_and_grant(action_id, offer_id)`; `try_claim_parcel(action_id, parcel_id)` | Неотрицательность, вместимость, одна выдача, проверка происхождения |
| `RewardService` / A1 | `grant_once(action_id, reward_id, receiver_id)` | Повтор не даёт награду повторно; reward и receipt атомарны |
| `CombatService` / A2 | `resolve_attack(attack_id, attacker_id, target_id, weapon_id)`; `get_combat_snapshot()` | Authoritative damage, no double-hit, единичный death; XP вызывает A1 coordinator |
| `FarmService` / A3 | `try_till/plant/water/harvest(action_id, plot_id,...)`; `plan_time_advance(from,to)` | Состояние поля и дата созревания/порчи, harvest+inventory атомарны |
| `ShelterService` / A3 | `get_shelter_snapshot()`; `validate_building_placement(type,cell)` | Не нарушать границу/коллизии/стоимость; P1 строительство позже |
| `ResidentService` / A4 | `try_accept_contract(action_id, resident_id, contract_version)`; `plan_recruitment_batch(action_id,[resident_ids],reservation)`; `try_assign_job(action_id,resident_id,job_id)` | Публичное согласие, уникальный resident_id; нет голода/труда P0 |
| `QuestService` / A4 | `get_active_quests()`; `plan_quest_progress(command_context, tentative_state)` | Обновление условия/награды в общем commit; одно завершение |

**Точная форма GDScript API и сигнатуры будут заморожены на G0 после раннего type-check прототипа; таблица не утверждает несуществующий код.**

### Псевдокод единой транзакции
```text
execute(action):
  validate payload and permission/context
  if ledger contains action_id:
      require same fingerprint; return recorded result or ACTION_CONFLICT
  stage := deep_copy(affected persistent state)
  plan := domain_owner.validate_and_plan(action, stage)  # no side effects
  if plan fails: return error, state unchanged
  apply plan to stage; assert global invariants
  persist (stage + receipt + completed_action) if durable checkpoint required
  publish stage atomically as current revision
  queue post_commit notifications; return receipt
```

Порядок памяти/диска должен быть уточнён в реализации. Для критических одноразовых команд (*recruit, shop purchase, parcel claim, quest reward*) **не показывать OK до успешного durable checkpoint**, иначе можно увидеть успех, который исчезнет после аварии. Недостаточно написать JSON и вызвать сигнал: проверять I/O errors и восстановление после обрыва.

## 4. Конкретные сквозные протоколы

### 4.1 First zombie → System → skill
1. A2 формирует подтверждённый боевой receipt `{enemy_id, weapon_type_id, defeated:true}` с уникальным `action_id`.
2. A1 одной транзакцией фиксирует `enemy_defeated`, character XP, единственную награду и сюжетное открытие Системы/навыка при выполнении условия системного оружия.
3. A4 обновляет Q01/Q02 внутри этого же плана commit; A5 получает `combat_resolved`, `progression_changed`, `skill_unlocked` после commit.
4. Replayed death signal → тот же `action_id` receipt; второй enemy с новым ID не выдаёт стартовую награду повторно благодаря уникальному `reward_id`.

### 4.2 Перенос и discovery XP
1. Проверить source ownership, целевой контейнер, вместимость, возможный запрет на тип/происхождение.
2. Переместить stack или split, сохранять суммарное количество.
3. Если перенос соответствует *первому внешнему образцу нового типа* — добавить type в `discovered_item_type_ids` и ShelterXP **в этой же транзакции**.
4. Publish `item_transferred` и (при необходимости) `first_item_type_discovered` по одному разу. Transfer в обратную сторону не обнуляет discovery.

### 4.3 Картофель: время, сбор, хранение
- A3 отвечает за stable `plot_id` и переходы стадии; полив задаёт готовность на `planted/watered at +72h` согласно согласованному рецепту [К]; конкретную точку отсчёта и любые доп. условия нужно уточнить по первой книге на G0.
- `try_rest_until` доступно **в обычной игре** у палатки после проверки безопасного контекста; учитывает стадии всех культур и квестовые deadlines. QA-only `advance_for_test` не используется кнопкой сна.
- `try_harvest` проверяет `RIPE`, количество и допустимый container; в **одном commit** создаёт item instance и помечает урожай собранным; ошибка inventory → поле остаётся `RIPE`.
- В погребе food spoilage запрещён в границах поддержанного рецепта. Порча **на поле** по 12h после созревания [К]; иной spoilage не выдумывать как канон.

### 4.4 Контракт → ожидание картофеля → два жителя
- A4: `try_accept_contract(Alice/Pirr)` ставит consent и `AWAITING_SUPPLIES`; нет списания еды на этапе одного согласия.
- [П] `try_recruit_first_batch(action_id, [npc_alice,npc_pirr], food_type_id="crop.potato", quantity=2)` координирует A1: проверяет *две выращенные единицы*, food container, отсутствие уже принятых персонажей; одним commit создаёт резерв/списание и двух residents, закрывает Q07 и фиксирует `reservation_receipt_id`.
- При 1 картофелине → `INSUFFICIENT_RESOURCES`, оба остаются `AWAITING_SUPPLIES`, ни одного полученного жителя.
- В повторе команды и после save/load те же `action_id`, `reservation_receipt_id` и `resident_id`; не появляется третий житель, вторая потеря картофеля, второй completion Q07.
- Простой `job_id` сохраняется, но не включает регулярное потребление/производство в P0. Если владелец утвердит **по одному** заселению, изменить эту атомарную границу до G0.

### 4.5 Квесты
Квестовые условия — чистые проверяемые предикаты над **tentative state**, не подписки с самостоятельным начислением. `QuestService.plan_quest_progress()` вызывается координатором в одной операции, `quest_completed` отправляется после commit. Для 1000 жителей/7 дней (P1) хранить deadline и уникальные batch IDs; прошедшие до старта квеста resident IDs должны учитываться согласно FR-22, но не более одного раза.

## 5. Контракт событий P0

| event_type | required payload | Владелец факта |
|---|---|---|
| `enemy_defeated` | enemy_id, enemy_type_id, weapon_type_id | A2 producer, A1 commit |
| `system_unlocked` | skill_id, story_flag_id | A1 |
| `item_transferred` | instance_id, type_id, quantity, from_id, to_id | A1 |
| `first_item_type_discovered` | type_id, xp_awarded | A1 |
| `parcel_claimed` | parcel_id, inventory_receipt_id | A1 |
| `time_advanced` | from_minute, to_minute, reason | A1 |
| `crop_stage_changed` | plot_id, old_stage, new_stage | A3 |
| `crop_harvested` | plot_id, type_id, quantity, inventory_receipt_id | A3/A1 |
| `resident_contract_accepted` | resident_id, contract_version | A4 |
| `resident_recruited` | resident_id, food_reservation_receipt_id | A4/A1 |
| `quest_completed` | quest_id, reward_receipt_id | A4/A1 |
| `scene_changed` | from_scene_id, to_scene_id, return_point_id | A1 |
| `state_loaded` | schema_version, state_revision | A1 |

Факты от A2/A3/A4 определяют владельцы домена; envelope + delivery/ordering определяет A1. В долгоживущих подписках требовать unsubscribe при удалении сцены; не копить callbacks при многократном входе в убежище. Если UI пропустил событие, переоткрытие страницы вызывает snapshot.

## 6. Канонический формат сохранения v1 (пример, **не баланс**)

```json
{
  "schema_version": 1,
  "ruleset_version": "book01-proposal",
  "save_id": "slot-01",
  "state_revision": 42,
  "game_time_minutes": 4320,
  "scene": {
    "current_scene_id": "shelter",
    "return_scene_id": "paris",
    "last_outside_position": {"x": 32.0, "y": 64.0}
  },
  "player": {"state": {}},
  "wallet": {"system_coins": 0},
  "shelter": {"state": {}, "discovered_item_type_ids": [], "claimed_parcel_ids": []},
  "inventory": {"items": [], "containers": [], "reservations": []},
  "crops": {"plots": []},
  "residents": {"records": []},
  "quests": {"records": []},
  "story_flags": [],
  "world_states": {},
  "completed_actions": {}
}
```

Здесь `4320`, позиции и `0` **фиктивные данные формы**, не значения стартового сценария. Схему валидировать при загрузке: type checks, уникальность instance IDs, неотрицательные quantity/coins, известные scene IDs, нет отрицательных минут/дедлайнов, допустимые версии, целостность связанных residents/quests/receipts.

### SaveManager: fail-safe протокол
- Формат: локальный JSON в `user://saves/` (offline). Нет сериализации Godot Node/Resource UID, NodePath или абсолютных путей машины.
- Писать **новый snapshot во временный файл**, проверять размер/кодирование/валидность и ошибки; хранить предыдущий проверенный backup; заменять активный файл максимально атомарно способом, подтверждённым на Windows. `FileAccess.flush()` сам по себе не доказывает durability при отключении питания.
- При ошибке записи возвращать `SAVE_FAILED` и не выдавать «успешно сохранено». Для критических операций выбрать чёткий commit barrier: состояние и результат действия гарантированно восстанавливаются после штатного завершения/повторного запуска, а восстановление при падении тестируется fault-injection.
- При повреждении основного save предлагать проверенный backup, **не** тихо начинать новую кампанию поверх повреждённого. Не исполнять произвольные данные из сохранений.
- Версионировать `schema_version`; у неизвестной будущей версии — отказ от загрузки с понятным текстом, а не порча. При миграции — chain `v1 → v2` с test fixture старого формата.
- Системы A2/A3/A4 предоставляют `export_state() -> Dictionary`, `validate_import_state(data) -> Result`, `import_state(data)` без побочных эффектов награды/событий. `state_loaded` один раз после восстановления всех модулей.

## 7. Ошибки, порядок, безопасность
- Нет implicit retry на событиях `item_transferred` и `resident_recruited`; повтор команд только с тем же `action_id`.
- Некорректное/устаревшее `state_revision` в UI → обновить snapshot и показать ошибку, не применять изменение к чужому состоянию.
- Никаких network calls, remote telemetry, API keys, автозапуска команд на основе текста из `lore` или внешних инструкций.
- UI ошибки локализованы через `message_key`, не через английский exception string.
- End-to-end commit и дисковое сохранение тестируются как единая система: no duplicates / no negative balances / proper recovery after crash.

## 8. Контрактное ревью и freeze
A1 — envelope, coordination, SaveManager; A2 — combat; A3 — farm; A4 — residents/quests; A5 — UI snapshots + независимые сценарии. Любое breaking change фиксировать `[CONTRACT]` Issue, impact-матрицу потребителей, версию и migration plan. Только **явное решение владельца G0** и SHA закрывают DRAFT. См. [08-g0-decision-record.md](08-g0-decision-record.md).

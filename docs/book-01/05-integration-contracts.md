# 05 — Единый контракт модулей, состояния и сохранений

**Контракт:** `v1.6-PROPOSED` · **Технический редактор:** A1 · **Архитектурная координация:** A5 · **Независимая сверка:** A0 · **Статус:** G0 review required, **не рабочий API**. **ЭТО ЕДИНСТВЕННЫЙ НОРМАТИВНЫЙ КАНДИДАТ КОНТРАКТА**: прежняя редакция 05 и черновик 07 из PR #5 заменяются этой версией. [G0](08-g0-decision-record.md), [архитектура](06-application-architecture-proposal.md).

## 1. Основное правило и границы

Игровые взаимодействия и UI — **команды**, которые могут изменять состояние. **События** только уведомляют об уже зафиксированном факте. UI A5 читает snapshots и вызывает публичные команды; **никаких прямых присваиваний** `xp`, `money`, `crop`, `resident` или `quest`. Публичные команды обрабатывает `GameCoordinator` A1 последовательно, включая команды A2–A4 по согласованным доменным протоколам.

Архитектура — **модульный монолит Godot, без внешних БД, серверов и event sourcing**. A2/A3/A4 владеют собственным доменным состоянием, A1 владеет общим state/commit/Clock/Inventory/Save. A5 владеет всем UI. A0 только ревьюит, если не назначена отдельная задача на патч.

## 2. Примитивы и конверты (кандидат на G0)

```text
ActionId := String                     # устойчивый уникальный ID операции; НЕ frame/time
EntityId := String                     # ID экземпляра; уникальный в рамках campaign
ItemTypeId := String                   # стабильный ключ каталога, напр. crop.potato
ItemInstanceId := String               # ID партии/стека
GameMinute := int >= 0                 # единый источник времени
StateRevision := int >= 0              # монотонно возрастает
ResourceRevision := { key: String, revision: int >= 0 }  # версия конкретной записи/контейнера

CommandRequest := {
  action_id: ActionId,
  command_type: StringName,
  context: { scene_id, actor_id, expected_resource_revisions? }, # [{key,revision}, ...]
  payload: Dictionary
}
CommandResult := {
  ok: bool, code: ErrorCode, action_id: ActionId,
  state_revision: int, data: Dictionary, message_key: String
  # STALE_REVISION: data содержит conflict_keys или UI заново запрашивает snapshot
}
ErrorCode :=
  OK | ALREADY_APPLIED | ACTION_CONFLICT |
  INVALID_ARGUMENT | INVALID_STATE | NOT_FOUND |
  INSUFFICIENT_RESOURCES | CAPACITY_EXCEEDED |
  REQUIRES_CONSENT | NOT_IN_SAFE_AREA | PAUSED |
  STALE_REVISION | TRANSFER_FORBIDDEN | SAVE_FAILED | UNAVAILABLE

DomainEvent := {
  event_id: String, event_type: StringName, action_id: ActionId,
  game_minute: int, state_revision: int, payload: Dictionary
}
```

**Смысл полей:** `event_type` — вид уведомления, `event_id` — уникальный факт, `action_id` — ключ идемпотентности команды, `state_revision` — версия авторитетного состояния. **Нельзя** называть `event_id` типом события как в старом EventBus. Предлагаемый интерфейс: `EventBus.publish_after_commit(event: DomainEvent)`. Слушатель события не выдаёт награду повторно.

**Повтор команды:** тот же `action_id` + тот же fingerprint **семантических** параметров запроса возвращает записанные data/revision с `ok=true, code=ALREADY_APPLIED`, без мутаций; тот же `action_id` + иная целевая операция/payload → `ACTION_CONFLICT`. `expected_resource_revisions` и другие служебные сведения о пересылке не должны менять fingerprint уже исполненного действия. Новый осознанный клик на покупку получает новый `action_id`; повтор доставки старого клика сохраняет ID. Для однократных наград проверять ещё устойчивый `reward_id`/`enemy_id`, а не только `action_id`.

**Нормализация fingerprint:** сохраняемый ключ составляется из `command_type`, нормализованного доменного `payload`, стабильного `actor_id` и целевых сущностей. Временные `scene_id`, текущие UI resource revisions, transport retry count и порядок JSON-ключей **не должны** менять идентичность уже исполненной команды при повторной доставке после загрузки. Повтор с тем же `action_id` проверяется **до** валидации текущего контекста/сцены; прошлый успех возвращается из ledger, даже если игрок уже ушёл с той карты. Новое сознательное действие с иными параметрами имеет другой `action_id`. Failed validation без commit не создаёт фиктивной квитанции успеха.

**Optimistic concurrency:** `state_revision` — монотонный номер общего snapshot для уведомлений/сохранений. Он может меняться при обычном ходе Clock. `CampaignSnapshot.resource_revisions` — словарь **ключ ресурса → его ревизия**, например `inventory:player`, `offer:system_seed`, `resident:npc_alice`. Для расхода/перемещения клиент передаёт `context.expected_resource_revisions=[{key,revision}, ...]` для **всех затронутых и показанных ему в подтверждении сущностей**, а координатор сравнивает их перед мутацией. Иначе покупка может ошибочно пройти на устаревшем ассортименте/ресурсе. Clock-only изменение общего `state_revision` **не** делает кнопку магазина устаревшей. Возвращать `STALE_REVISION` только при конфликте конкретной сущности; UI получает свежий snapshot. В MVP можно использовать ревизии по контейнеру и NPC, без дорогостоящей полной распределённой MVCC.

## 3. Публичные фасады и владельцы

| Фасад | Владелец | Команды / запросы (псевдосигнатуры до реального type-check) |
|---|---|---|
| `GameSession` | A1 | `new_campaign(seed?)`, `get_snapshot()->CampaignSnapshot`, `acquire_pause(reason)->token`, `release_pause(token)` |
| `GameCoordinator` | A1 | `execute(request:CommandRequest)->CommandResult`; сериализация, validation, commit, notifications |
| `SceneRouter` | A1 | `try_transition(action_id,destination_scene_id,entry_point_id)` |
| `GameClock` | A1 | `get_game_minute()->int`, `try_rest_until(action_id,target_minute,context)`, `advance_for_test(minutes)` **QA-only** |
| `InventoryService` | A1 | `try_transfer(action_id,instance_id,from,to,quantity)`, `try_spend_and_grant(action_id,offer_id)`, `try_claim_parcel(action_id,parcel_id)` |
| `ProgressionService` | A1 | `apply_combat_reward_once(action_id,combat_receipt)`, `register_first_item_type(action_id,type_id)` |
| `FarmService` | A3 | `try_till/plant/water/harvest(action_id,plot_id,...)`, `plan_time_advance(from,to)` |
| `CombatService` | A2 | `resolve_attack(attack_id,attacker,target,weapon)`, `get_combat_snapshot()` |
| `WorldResourceService` | A2 | `plan_claim_resource(action_id,resource_node_id)`, `get_resource_snapshot()`; A1 atomically adds reward and persists cooldown |
| `ResidentService` | A4 | `try_accept_contract(action_id,resident_id,version)`, `plan_recruitment(action_id,resident_ids,food_rule_id,food_selection?)`, `try_assign_job(action_id,resident_id,job_id)` |
| `QuestService` | A4 | `get_active_quests()`, `plan_quest_progress(tentative_state)` |
| `UILayer/ViewModels` | **A5** | `render_snapshot()`; UI triggers commands and displays `message_key`; **does not mutate game data** |

Кандидат версий контрактов должен быть подтверждён ревью **A1–A5**, A0 выполняет независимую трассировку и ревью UI. Реальные GDScript имена/типы проверяются при bootstrap G1a без произвольного изменения внешних гарантий.

## 4. Инварианты и транзакции

1. **Одна операция — один эффект.** Нельзя выдавать награду, XP, посылку, жителей или создавать урожай дважды при повторе, reload или двойной подписке.
2. **Состояние меняет владелец через coordinator:** A2 — подтверждение попадания/смерти, A3 — поле/постройка, A4 — согласие/квест. A1 — XP, кошелёк, инвентарь, квитанции, единое состояние и commit. **Не делать доменную запись в EventBus listener.**
3. **Cross-domain action** (сбор→инвентарь; еда→житель; покупка→предмет; убийство→XP/квест) имеет единый validate/plan/commit. Невозможно частично списать еду и не заселить NPC; ошибка переполнения не может «убрать» урожай.
4. **Ревизия UI:** если изменилась важная для операции версия одной из затронутых сущностей, вернуть `STALE_REVISION` и обновляемый snapshot, не применять старый выбор. **Обычный тик игрового Clock сам по себе не основание для отказа**.
5. **Отрицательные значения:** количество, деньги, прогресс и таймеры валидируются; есть ID типов и экземпляров, не используем отображаемое имя как ключ.
6. **Одноразовые награды:** сериализуются `claimed_parcel_ids`, `discovered_item_type_ids`, `completed_actions`, `recruited_resident_ids`, `reward_ids`, применённые задания.

### Протокол commit

```text
execute(request):
  if action_id already committed: check semantic fingerprint; return recorded result or ACTION_CONFLICT
  validate request, context, expected affected-resource revision
  tentative = copy(affected authoritative DTOs)
  domain_owner.validate_and_plan(tentative, request)  # no UI/signal side-effects
  coordinator.assert_invariants(tentative)
  if invalid: return error (no mutation)
  if durable action: persist full coherent checkpoint + receipt or return SAVE_FAILED
  publish tentative as new authoritative revision
  enqueue DomainEvent(s) after commit
  return CommandResult + receipt
```

Здесь `durable action` — критичная одноразовая покупка/награда/заселение/посылка и явный save. Другие действия сохраняются по разумному автосейву; до фактической записи не обещать устойчивого сохранения. **Частые `move/aim/dodge/attack frame` не пишутся на диск и не требуют persistent `action_id` для каждого кадра**: это боевой runtime A2. Граница транзакции проходит по долговременному результату (смерть врага, XP/лут, уникальное раскрытие), а не по каждому кадру анимации. Для выдачи результата боевого столкновения используются устойчивые `enemy_id` и `reward_id` с общей командой A1. G1a обязан проверить порядок атомарной смены файла и памяти и сценарии падения на Windows.

## 5. Порядок времени и safe rest

- Авторитетный **игровой календарь** — целые `game_time_minutes` (сельское хозяйство, порча, сюжетные дедлайны); `minutes_per_real_second` хранится в `game_balance`. A1 накапливает **дробный остаток реального delta** и повышает календарную минуту при переходе границы, иначе скорость будет зависеть от FPS. **Реальное время A2 (physics delta, attack cooldown, i-frames dodge, animation)** является отдельной runtime-метрикой, не общим вторым календарём; на паузе бой и календарь останавливаются вместе. Нельзя менять время роста из physics frame напрямую.
- Для каждой культуры `grow_minutes`, `spoil_minutes` находятся в версии правил. Книжный картофель 72/12 игровых часов — **референс**, не неизменяемый hardcode. Тесты используют активное значение конфига, отдельно могут проверять референсную фикстуру.
- Игрок может **безопасно отдыхать** в зоне палатки до ближайшей зрелой культуры или выбранного допустимого времени: UI A5 → команда `GameClock.try_rest_until(...)` A1. При опасности/боевой активности или невозможном deadline → понятный отказ без изменения времени.
- **Один скачок** времени обязан корректно обработать рост/порчу ВСЕХ полей, релевантные deadlines/квесты, дискретные правила и системные уведомления в детерминированном порядке `tentative_clock → domain plan → commit → ordered events`. На больших скачках при интерактивном событии — остановка/предупреждение, а не молчаливое пропускание обязательного выбора.
- `advance_for_test(minutes)` существует **только в QA окружении** и не подключён к обычному UI. Пауза останавливает игровой clock, но не управление меню.

## 6. Запас еды для заселения (без захардкоженных двух картофелин)

```text
arrival_food_requirement := {
  rule_id: String,                  # версия правила баланса
  accepted_food_type_ids: [String],# например crop.potato; список задаёт баланс
  units_per_resident: int >= 1,    # количество >0; баланс A3/A5
  reserve_mode: "reserve" | "consume"   # P0 предпочтительно reserve
}
```

**Валидация правила:** `accepted_food_type_ids` — непустой список допустимых типов, `units_per_resident` — положительное целое, `reserve_mode` — один из перечисленных вариантов. Тем самым действительное требование еды не может быть нулевым. `ruleset_version` фиксируется в save; смена продовольственного правила между сохранениями допускается лишь с явной миграцией/проверкой старого резерва, а не тихим пересчётом.

Конфиг/формула `needed_units = units_per_resident × количество заявленных жителей` — пример общего правила. Более сложная структура допускается через версию `food_rule_id`. **Никаких 2 картофелин как обязательной нормы.** Можно тестировать `units_per_resident = 1` и `3` как фикстуры; это не утверждение реального баланса.

**Выбор еды:** если пользователь выбирает конкретные стеки, `food_selection` содержит количество каждого допустимого `type_id` и проходит проверку суммарной нормы; если выбор автоматический, A1 применяет детерминированный порядок `accepted_food_type_ids` из версионированного правила. Квитанция сохраняет фактический состав резерва по типам; другие запасы и зарезервированные единицы нельзя использовать одновременно. При `reserve_mode=reserve` они недоступны остальным покупкам/операциям до явного освобождения по правилу; при `consume` — списываются один раз.

**Поток:** A4 фиксирует информированное добровольное согласие, NPC остаётся `AWAITING_SUPPLIES`; A1 проверяет конфиг и доступный food container; в **одном commit** создаёт уникальный резерв с `reservation_receipt_id`, переводит уникальных NPC в `RECRUITED`, обновляет Q07 и выдаёт награды. Нехватка еды → никакого частичного списания и заселения. Повтор того же action/попытка с другим action после успеха не повторяет эффект; для нескольких NPC в batch — все-or-none, для отдельного человека отдельная транзакция. P0 сохраняет `job_id`, но регулярные голод/труд — P1.

### 6.1. Возобновляемый источник для защиты от softlock (P0)

A2 предусматривает **как минимум один доступный узел обычных семян/ресурсов** за пределами необязательных квестов. Конфигурация `resource_respawn_minutes: int > 0` (первый кандидат: 1440 игровых минут, не утверждённый баланс). `resource_node_id` имеет устойчивую идентичность, `next_available_game_minute` сохраняется в `world_states`. A2 формирует план `plan_claim_resource`, A1 атомарно проводит Inventory + обновление cooldown + событие после commit. После повторного входа в город узел не восстанавливается досрочно. При заполненном инвентаре нет потери предмета или незаконного обновления cooldown. Это **обычный восполняемый ресурс**, а не повторяемая уникальная сюжетная награда.

**Проигрыш в P0:** A2 возвращает героя на зафиксированную безопасную точку/чекпойнт через A1 SceneRouter, с корректным восстановлением состояния боя, без удаления кампании и без повторного System unlock. Инвентарь и одноразовые rewards сохраняются по ранее завершённым транзакциям; нестандартный штраф не вводить без принятой настройки баланса.

## 7. События P0 после commit

| event_type | Минимальные поля payload | Владелец факта |
|---|---|---|
| `enemy_defeated` | enemy_id, enemy_type_id, weapon_type_id, is_system_weapon | A2 + A1 commit |
| `world_resource_claimed` | resource_node_id, item_type_id, quantity, next_available_game_minute | A2/A1 commit |
| `system_unlocked` | reward_id, skill_id | A1 |
| `scene_changed` | from_scene_id, to_scene_id, entry_point_id, return_scene_id | A1 |
| `item_transferred` | instance_id, type_id, quantity, from_id, to_id | A1 |
| `first_item_type_discovered` | type_id, xp_awarded | A1 |
| `parcel_claimed` | parcel_id, receipt_id | A1 |
| `time_advanced` | from_minute, to_minute, reason | A1 |
| `crop_stage_changed` | plot_id, old_stage, new_stage | A3 |
| `crop_harvested` | plot_id, type_id, quantity, inventory_receipt_id | A3/A1 |
| `resident_contract_accepted` | resident_id, contract_version | A4 |
| `arrival_food_reserved` | reservation_receipt_id, food_rule_id, items:[{type_id,quantity}], total_units | A1 |
| `resident_recruited` | resident_id, reservation_receipt_id | A4/A1 |
| `quest_completed` | quest_id, reward_receipt_id | A4/A1 |
| `state_loaded` | schema_version, state_revision | A1 |

UI A5 переполучает snapshot после `state_loaded`. EventBus listeners отписываются при уничтожении сцены; повторное открытие меню не должно создавать N подписок. Прогресс квеста вычисляется внутри транзакционного плана; event только уведомляет о завершении.

## 8. Сохранение и отказоустойчивость

**Схема ниже — историческая иллюстрация `schema_version=1`, НЕ валидная фикстура игрового `schema_version=4`.** Реальная форма кампании v4 и ограничения миграции перечислены в §17 и проверяются через `CampaignModel.new_state()/validate()`. Нельзя создавать v4 save простым изменением одного числа в этом примере.

```json
{
  "schema_version": 1, "ruleset_version": "g0-candidate",
  "save_id": "slot-01", "state_revision": 0, "game_time_minutes": 0,
  "resource_revisions": {"inventory:player": 0},
  "scene": {"current_scene_id": "hospital", "return_scene_id": null, "last_outside_position": null},
  "player": {"state": {}}, "wallet": {"system_coins": 0},
  "shelter": {"state": {}, "discovered_item_type_ids": [], "claimed_parcel_ids": []},
  "inventory": {"items": [], "containers": [], "reservations": []},
  "crops": {"plots": []}, "residents": {"records": []},
  "quests": {"records": []}, "story_flags": [], "world_states": {},
  "completed_actions": {}, "claimed_reward_ids": []
}
```

Это **пример формы**, не стартовые значения баланса. Запрещены `NodePath`, живые Node/Texture/Signal, абсолютные пути. Данные сохраняются в `user://saves/` локально на Windows. Для критичных операций — coherent snapshot + receipt. Писать temp и проверять результат, хранить прошлый валидный backup, использовать безопасную замену файла с проверенной на Windows семантикой. `FileAccess.flush` сам по себе не гарантирует переживание внезапного отключения питания; не обещать не проверенную durability.

При повреждённом основном save → предложить проверенный backup/ошибку, **не** запускать тихо новую кампанию поверх данных. Неизвестную будущую схему отклонять без уничтожения файла; chain миграций `v1→v2` тестировать на фикстуре при появлении версии 2. A2–A4: `export_state()`, `validate_import_state(data)`, `import_state(data)` без выдачи наград. Сохранение и восстановление проверяются после restart.

## 9. Конкретные негативные случаи и приемка контракта

- Дубли action/parcel/enemy/quest, одинаковый action_id с другим payload, повторная доставка после reload.
- Harvest на полный инвентарь; нет семян/воды/монет/еды; stale ресурсная версия; `units_per_resident=0` **отклоняется валидатором**, `1` и `3` — допустимые тестовые конфиги, не утверждённый баланс.
- Два разных поля, пересекающиеся deadlines при длинном отдыхе; пауза во время open modal; QA метод недоступен обычной игре.
- Save corrupted/truncated + backup; версия `schema_version` больше известной; двойной вход в сцену и повторное открытие UI.
- Игра остаётся функциональной, если Q03–Q07 не активированы.

Подробно — [10-qa-acceptance-matrix.md](10-qa-acceptance-matrix.md). Без фактического запуска все тесты **NOT_RUN**.

## 10. Изменения и заморозка

Этот контракт **не считается утверждённым до G0**. Breaking change: Issue `[CONTRACT]` + список потребителей + review A1–A5 + A0 по риску, версия, тест/миграция, новая ссылка на SHA. Сама работа над документацией и создание PR не означает разрешения писать Godot-код. Для G0 необходимы доказательства ревью и явное утверждение владельцем **точного commit SHA**.

## 11. Предложение уточнений по ревью 2026-11-06

**Статус:** PROPOSED по [Issue #15](https://github.com/AndreyCokol/My_shelter/issues/15), поверх кандидата `f790b20e91b6139de7c62823df1b6df899d8c8a1`. Требует согласования A1–A5; не утверждает G0.

### 11.1. Повтор команды и результат

При успешном replay возвращать `ok=true, code=ALREADY_APPLIED`, исходные `action_id`, `data` и `state_revision` из квитанции. Эта revision обозначает исходный commit, а не текущий мир. Для отрисовки UI запрашивает актуальный snapshot; старую квитанцию нельзя накладывать поверх нового состояния. При несовпадающем fingerprint: `ok=false, code=ACTION_CONFLICT`, без изменений. Все ошибки имеют `ok=false`; только OK и ALREADY_APPLIED имеют `ok=true`. Форма сериализованной квитанции: `{fingerprint, result: CommandResult}`; successful replay не создаёт новый commit, ревизию или события.

### 11.2. Граница записи и публикации

Commit point — успешная проверенная замена основного checkpoint, содержащего состояние и квитанцию вместе. До этой точки ошибка даёт SAVE_FAILED и сохраняет прежнее авторитетное состояние. После неё нельзя выдавать SAVE_FAILED как доказательство отката: действие уже сохранено. При невозможности опубликовать тот же checkpoint в памяти остановить новые изменяющие команды, перейти в recovery и перечитать сохранённую ревизию; повтор action_id возвращает сохранённый результат. Если исход замены файла неизвестен, также блокировать команды до сверки checkpoint/receipt, а не продолжать игру с предположением об откате. Падение после commit, до ответа/событий, не отменяет операцию. После restart UI строится из snapshot, пропущенные уведомления не нужны для выдачи наград.

### 11.3. Атомарная загрузка

Загрузка выполняется при остановленной симуляции и закрытом приёме изменяющих команд. Сначала прочитать, проверить schema/ruleset, все DTO, ссылки между доменами, уникальность ID, резервы и receipts в отдельное кандидатное состояние. Ни один import не должен менять живой домен до успешной общей проверки. Затем подготовить runtime-сцены/домены отдельно и заменить единую сессию целиком. Ошибка любого шага оставляет прежнюю сессию и файлы доступными; state_loaded посылается только после успешной замены. Backup восстанавливать после выбора пользователя тем же путём проверки. Во время state_loaded никакие listener не начисляют ресурсы.

### 11.4. Несколько причин паузы

`GameSession.set_pause(bool)` допустим только как внутренний адаптер агрегированного состояния. UI использует `acquire_pause(reason)->token` и `release_pause(token)`; token непрозрачный, освобождается владельцем ровно один раз, повторное освобождение безопасно. Симуляция стоит, пока существует хотя бы один token (меню, модальное окно, загрузка/recovery). Закрытие инвентаря не снимает паузу меню. При уничтожении UI освобождаются только его tokens; recovery token принадлежит A1. HUD не берёт token. После load tokens не восстанавливаются из save, актуальные причины создаёт текущий runtime. Escape закрывает верхний UI слой; этот же input не передаётся бою.

### 11.5. Порядок дедлайнов

И обычный tick, и отдых используют один планировщик. Обрабатывать границы на интервале `(from_minute, target_minute]` в порядке `(game_minute, phase_priority, stable_entity_id)`: сначала зрелость, затем порча, затем проверка сюжетных условий по полученному состоянию. Уведомления публикуются в этом же порядке после commit. При точном равенстве `now == ripe_at` культура ripe; при `now == spoil_at` spoiled и сбор отклоняется. Разные культуры с одним сроком не зависят от порядка Dictionary. Интерактивная остановка завершает время на выбранной границе и сообщает actual_to_minute; оставшаяся часть отдыха не исполняется автоматически. Большой скачок и несколько малых при отсутствии интерактивных остановок дают одинаковое доменное состояние.

## 12. A1-04: runtime сцены и координаты (2026-11-06)

Расширение по Issue #21, G0 review pending. Поддержанная схема campaign-core теперь schema_version=2: player.position={x,y}, scene.positions={scene_id:{x,y}}, scene.last_outside_position. Только конечные числовые координаты в пределах ±10000000; Node/NodePath в save отсутствуют. Схема 1 campaign-core отклоняется без перезаписи файла: автоматическая миграция не заявляется. core-bootstrap schema_version=1 — другой scope/slot.

SceneRouter принимает доверенный реестр scene_id→PackedScene из проекта, WorldHost и единственный Node2D героя от A2. Корень world и узел EntryPoints имеют identity transform; EntryPoints содержит Marker2D с entry_point_id. entry_point_id — идентификатор, не произвольный NodePath. Герой располагается отдельно от сменяемого декора внутри WorldHost, его экземпляр сохраняется. UILayer A5 остаётся вне сменяемого мира.

Порядок: coordinator сериализует команду → domain plan → общая validation → подготовка/проверка runtime ticket без attach → durable checkpoint → авторитетный snapshot → установка подготовленного world/позиции → committed/state_loaded. При ошибке подготовки или записи stage уничтожается, старый world и snapshot сохраняются. При сбое после commit coordinator блокирует изменения recovery-token; load снова готовит runtime из сохранённого snapshot. Установка подготовленного world — синхронный доверенный адаптер; сцены не должны исполнять доменные команды в _init/_ready. Если install не завершился, не обещать откат уже записанного commit: нужен recovery. Ошибки произвольных сторонних scene scripts не объявляются автоматически откатываемыми.

Позиции departure/arrival — вычисленные SceneRouter сведения runtime в context, не смысл нового действия и не часть fingerprint. Для UI канонический путь: router.try_transition(action_id,destination_scene_id,entry_point_id), router.save(action_id), router.load_saved(use_backup=false). save захватывает актуальную координату героя; переход сохраняет исходную и восстанавливает ранее посещённую точку либо Marker2D для нового назначения. Replay старого action возвращает receipt до проверки текущей сцены/ресурса и не монтирует старый world поверх нового. Изменение действия с тем же ID остаётся ACTION_CONFLICT.

Сохранять SceneRouter в Main на всё время жизни кампании; runtime_required запрещает незаметный переход к DTO-only, если назначенный adapter недоступен. Main.start_campaign(rules,worlds,actor,save_path) подключает supplied модули и запускает Clock; повторный старт в том же Main отклоняется. Без поставленных модулей Main остаётся техническим bootstrap, игровая готовность не заявляется.

## 13. A1-02: EventBus после commit (2026-11-06)

Реализация по Issue #23. GameCoordinator формирует DomainEvent из чистых domain drafts {event_type,payload}. Проверка draft выполняется до записи; malformed draft отклоняет команду целиком. События приходят только после успешного snapshot commit и runtime install, до compatibility committed signal. Порядок draft сохраняется. Идентификатор: save_id/scope + hash(action_id) + ordinal. События не являются хранилищем или источником начисления ресурсов.

EventBus.subscribe(owner,callback,event_types=[])->token принимает стабильный bound method владельца. Повтор той же подписки возвращает прежний token; unsubscribe(token) идемпотентен, unsubscribe_owner(owner) снимает подписки панели. Владелец хранится weak reference; уничтоженные/queued-for-deletion Node и невалидные callbacks удаляются перед доставкой. Панель, которая только скрыта, должна сама отписаться при закрытии. Новые подписки во время dispatch начинают получать следующий event; снятая подписка не получает оставшуюся доставку текущего event. String/StringName типов нормализуются в String.

Каждый слушатель получает собственную глубокую копию payload. Мутация event одним слушателем не влияет на другого или snapshot. Вызов команды во время dispatch отклоняется UNAVAILABLE, повторная публикация из callback отклоняется. UI обновляет view/snapshot, а не исполняет доменную логику в listener. Для действий после уведомления требуется отдельный осознанный пользовательский ввод после завершения commit.

Replay возвращает receipt без новых событий; ошибки validation/I/O и остановка после disk commit до runtime install не выдают успешные уведомления. После load/recovery очищается временная история доставки, сохраняются живые подписки и публикуется только state_loaded для snapshot refresh. Пропущенные игровые события не воспроизводятся: авторитетные последствия уже в coherent checkpoint. Domain idempotency основана на persisted receipts/reward IDs, не на временном EventBus dedup. In-memory history доставки живёт до load/new session.

Clock tick публикует time_advanced только при изменении целой календарной минуты и не пишет файл на каждом кадре. Rest публикует тот же envelope с reason=rest; tick с reason=tick. Реальные планы Farm/Quest пока не подключены; общий механизм calendar adapters описан в §14.

Дополнительные факты уже реализованного ядра:

| event_type | payload | Примечание |
|---|---|---|
| item_granted | instance_id, type_id, quantity, container_id | Источник — выполненный grant, не команда на выдачу |
| reward_claimed | reward_id, receipt_id | Не заменяет будущий combat receipt |
| progression_changed | hero_xp, shelter_xp | Итоговые раздельные счётчики |
| wallet_changed | system_coins | Итоговый баланс |
| checkpoint_saved | save_id | Revision в envelope |

Для scene_changed уточнено имя entry_point_id для целевой точки входа и отдельно return_scene_id; неоднозначное старое return_point_id не публикуется. Обновление интерфейса требует review потребителей A2–A5; реальных UI потребителей в текущем ядре ещё нет.


## 14. A1-02/04: общий calendar planner (Issue #25, proposed)

`CampaignSession.configure_calendar(provider, handler)->bool` — trusted setup API A3/A4 через A1, не команда UI. Оба Callable устанавливаются вместе; пустая пара снимает adapters, неполная пара отклоняется, во время coordinator transaction настройка запрещена. Владельцы adapters обеспечивают их lifetime; уничтоженный установленный callback блокирует время с UNAVAILABLE, а не снимает обработку дедлайнов молча. Схема campaign-core остаётся v2, callbacks не сериализуются.

- `provider(snapshot_copy, from_minute, target_minute)` возвращает полный массив deadlines интервала `(from, target]` либо `{ok:false}` при опасности/сохраняемом ожидающем выборе. Отказ даёт `UNAVAILABLE` для отдыха, `false` для tick и не меняет время. Provider чистый, без I/O/эффектов. Он обязан включить все производные границы (например зрелость **и** порчу), которые могут возникнуть в этом интервале. Динамическое достраивание очереди в этом API не реализовано.
- Deadline: `{minute: int>=0, priority: int>=0, entity_id: nonempty String, interactive?: bool}`. Один `(minute,priority,entity_id)` уникален; неверная форма, дубликат или граница вне интервала отклоняют весь план. Рекомендуемые priorities: 0 maturity, 1 spoilage, 2 story predicates. Handler сам определяет доменные правила.
- `handler(candidate, deadline)->{ok:bool, events?:Array}` меняет только tentative snapshot. Он видит календарь на минуте deadline, не меняет сам календарь, не отправляет события, не пишет файлы и не изменяет runtime. Ссылки на candidate не сохранять. Эффекты должны иметь доменную валидацию и resource revisions, когда затронут показанный игроку ресурс. Ошибка любого handler откатывает весь tick/rest, включая ранее запланированные эффекты. Фактические доменные validators/состояния A3/A4 ещё должны быть подключены; непустые placeholders текущим Model по-прежнему отклоняются.
- Единый `CalendarPlanner.advance` используется natural tick и `clock.rest`. Сортировка: minute, priority, stable entity ID. При первом interactive deadline выполняются **все** фазы этой минуты, поздние границы не выполняются; результат rest содержит `actual_to_minute` и `interrupted`. Остаток пропущенного кадра/отдыха автоматически не доигрывается. Handler обязан сохранить pending choice в своём домене, а provider — отказывать последующим попыткам времени до решения; одного transient уведомления недостаточно. Это ответственность будущего adapter, не готовая quest-система.
- Rest завершается на целой минуте с `clock_remainder=0`. Обычный tick сохраняет дробную часть; остановленный tick сбрасывает непройденный остаток. Конечность произведения delta/rate и предел JSON exact integers проверяются **до** float→int.
- После успешной установки состояния публикуются `time_advanced`, затем ordered domain drafts. Для deadline draft A1 ставит `game_minute=deadline.minute`; state_revision у всех событий — общая committed revision. Остальные события по умолчанию имеют минуту конечного snapshot. Неотрицательная минута draft не может превышать конечную минуту. События/receipt никогда не заменяют authoritative domain state.
- Rest проходит durable transaction с квитанцией; повтор не вызывает adapters. Tick проходит runtime validation barrier без записи на каждом кадре. Save failure до commit не публикует ни время, ни доменные события; после commit recovery читает сохранённый snapshot и посылает только refresh.

**Handoff:** A3/A4 предоставляют полный provider, чистые handlers, schema validators и persisted pending gates; A5 читает actual_to_minute/interrupted и обновляет UI из snapshot. API предложен для review A3/A4/A5, не объявлен согласованным ими. Проверки CT-44..47 используют технические adapters, не игровые поля/квесты.


## 15. Игровой прототип v3 (Issue #27, предложено для review)

Прямое поручение владельца выполнить все 17 шагов расширяет область одной сессии на игровые модули и UI. Это не шесть отдельных авторов/reviewers и не формальное G0 approve.

- `game/scenes/main/playable.tscn` — запускаемая композиция; прежний `main.tscn` сохраняет supplied campaign API и core fixtures. `GameApp.command(kind,payload)` — UI facade; trusted команды `game.enemy_defeated`/`game.player_defeated` через него запрещены. Combat вызывает их отдельными runtime hooks после подтверждённого состояния actor/enemy. Серверов/сети в игре нет.
- Gameplay catalogs: `game/data/game_rules.gd`. Правила — первоначальные кандидаты, а не подтверждённый баланс 15–35 минут. `CampaignSession.get_rules()` возвращает копию. UI не пишет state/rules.
- Gameplay state имеет `schema_version=3`, `ruleset_version=prototype-v1`, отдельный путь `prototype-v3.json`. Core-fixture v2 остаётся поддержан только своим ruleset. Автоматическая миграция v2→v3 не заявляется: несовместимый файл отклоняется без перезаписи. Новая игра — явный выбор с архивированием старых primary/backup.
- Persisted domains: два plot ID и стадии empty/planted/growing/ripe/spoiled; два resident ID со status/consent/food_receipt_id; Q01–Q07, story flags, first enemy ID, resource cooldown и defeats. Валидатор проверяет известные IDs/status, сроки из rules, вместимость из каталога, ссылки/суммы food reservations и joined receipt. Core проверяет всю сессию до runtime swap.
- Типизированные UI команды: `game.plant/water/harvest/clear {plot_id}`, `game.resource_collect {}`, `game.contact/recruit {resident_id}`, `game.consent {resident_id,accept}`, `game.quest_track {quest_id}`. Требуются revisions world/farm/residents и обоих контейнеров. Generic inventory/clock/scene/save команды сохраняются. Q03–Q07 inactive не мешают механикам.
- Посадка расходует свободное семя; вода в убежище доступна; полив начинает configured grow/spoil deadlines. Calendar provider заранее включает зрелость и порчу всех полей. Harvest + inventory + XP + receipt — одна транзакция; полный рюкзак оставляет ripe plot. Порча ровно на spoil_at блокирует сбор.
- Контакт и согласие отдельны от заселения; отказ не выдаёт жителя. При нехватке пищи остаётся AWAITING_SUPPLIES. Recruit использует positive configured units, accepted types, reserve/consume. Receipt содержит resident_id, фактические instance/type/quantity allocations, mode и units. Резерв ограничивает inventory transfer и любой расход через available quantity.
- Runtime health/attack/dodge/enemy AI используют physics delta и останавливаются при агрегированной паузе. Атаки не пишут диск; первая смерть и награда сохраняются вместе. Здоровье/координаты героя сохраняются явным Save; смерть создаёт durable safe respawn. Состояние промежуточного удара/анимации не сохраняется, живой враг при загрузке восстанавливает здоровье. Незавершённый бой при restart начинается заново без повторной уже выданной награды.
- UI modal владеет одним pause token. Для синхронной команды панель временно отпускает только свой token и восстанавливает его без промежуточного кадра; чужой token/recovery продолжает блокировать изменения. Save допускается из меню. Escape закрывает окно, снимает его focus и token; навигационные кнопки не перехватывают Space для боя после закрытия.
- `preview_rest(target)` планирует на отдельной копии без commit и возвращает фактическую минуту/число spoiled plots. Подтверждение исполняет обычный clock.rest. Рендер/UX/доступность проверяются отдельно от headless DTO/E2E тестов.
- JSON checkpoints используют full_precision=true для сохранения дробного Clock/координат без потери точности. Engine notices входят в архив сборки; lore/docs/tests исключены из экспортируемых ресурсов.

Статус: реализовано и проверяется в integration branch; независимый review NOT_PERFORMED. Windows headless CI не является human GUI/UX acceptance. Полная готовность G4 требует оставшихся доказательств.

## 16. P0: безусловный перенос в убежище (решение владельца 08.11.2026)

**Инвариант:** способность войти в пространственное убежище и вернуться к месту последнего выхода не зависит от `first_enemy_defeated`, `system_unlocked`, Q01/Q02, денег, еды, кулдауна или наличия физического выхода. Правило действует из всех активных сцен, включая бой. Стартовые награды за первый бой и доступ к System shop по-прежнему gated.

**Единственная авторизованная запись:** A5 вызывает `GameApp.toggle_shelter()` по `G` или из UI; фасад делегирует в A1 `SceneRouter.try_transition(action_id, target, "default", actor_health?)` и CoreSession. SceneRouter атомарно сохраняет `scene.positions`, `scene.return_scene_id`, `player.position` и текущий `player.hp` при переходе. После save/load обратная команда возвращает к исходной позиции, не подменяя `claimed_reward_ids` и `enemy_id` и не добавляя XP. Доказательство — CT-48..52.

**Паузы:** если открыт собственный модальный UI A5, он освобождает **только свой** pause token перед синхронной командой и закрывается при успехе; при неудаче восстанавливает прежний экран и уведомление. Чужая пауза, recovery после неудачного durable commit и активная загрузка не снимаются: переход отвергается с сохранением исходного состояния. После поражения герой восстанавливается через checkpoint, не телепортируется в обход механики смерти.

**Rollback:** при `SAVE_FAILED` новая сцена и позиция не публикуются и остаются доступными предыдущие сцена/ресурсы/receipt. Игровое время не ускоряется и не прерывается сверх естественной паузы UI; смена scene не создаёт права на повторение уникальной награды. Ревью A1/A2/A5 и независимый A0 остаются необходимы перед merge.

## 17. Runtime-v4 contract reconciliation 08.11.2026 — единый кандидат v1.6

**Статус:** `CODE_AUDITED / CI_VERIFIED / DOMAIN_REVIEWS_PENDING`; этот раздел актуализирует исторический §15 (v3), не является новым вторым контрактом. Исходная интеграция: [PR #50](https://github.com/AndreyCokol/My_shelter/pull/50), crop/save fix [PR #51](https://github.com/AndreyCokol/My_shelter/pull/51), melee LOS [PR #52](https://github.com/AndreyCokol/My_shelter/pull/52), perf/event history [PR #53](https://github.com/AndreyCokol/My_shelter/pull/53). Каждая ветка имеет собственный проверяемый SHA; старые PR #38 и #39 являются **источниками PR #50, не отдельными требованиями к слиянию**.

### 17.1 Точная схема и API реализации

- **Gameplay campaign save:** `schema_version=4`, `scope="campaign-core"`, `ruleset_version="prototype-v1"` (текущее значение, не обещание неизменности). `CampaignModel.new_state()` создаёт base v2, `GameplayState.seed()` добавляет домены v3, при `rules.world_seed` создаётся v4 с `world_states.layout` и `world_states.locations`. Реальные данные: `save_id`, `state_revision`, `game_time_minutes`, `clock_remainder`, `resource_revisions`, `scene{current_scene_id,return_scene_id,entry_point_id,positions,last_outside_position}`, `player{xp,position,hp}`, `wallet`, `shelter`, `inventory{items,containers,reservations}`, `crops.plots`, `residents.records`, `quests.records`, `story_flags`, `world_states`, `completed_actions`, `claimed_reward_ids`. Внешняя минимальная JSON-форма НЕ заменяет вызов `new_state()` и всё глобальное validation.
- Принимаются конкретные совместимые формы v3 как `legacy` только при проверках `CampaignModel.validate()`; это **не** общая миграция v1/v2/v3/v4. Неизвестный `ruleset_version` и произвольная несовместимая схема отклоняются, источник/backup не затираются.
- `GameApp.command(kind,payload)` формирует типизированный контекст с актуальными `resource_revisions` и уникальным `action_id`; trusted combat-команды недоступны этому UI фасаду. `CoreSession.execute()` валидирует, планирует, коммитит snapshot+receipt, затем публикует уведомления. `SceneRouter.try_transition(action_id,destination_scene_id,entry_point_id,actor_health)` записывает сцену, позицию и HP в общую durable transaction.
- Реализация `GameApp.next_action()` на данный момент использует сочетание `Time.get_unix_time_from_system()`, `Time.get_ticks_usec()` и локального счётчика; это **не гарантированный долговременный монотонный протокол**. Нельзя безопасно выкидывать старые `completed_actions` без новой схемы ActionId/водяного знака и миграции. Рекомендация владельцу A1: версионировать `campaign_id/issuer_id/sequence`, persisted `last_seen_seq`, вводить `REPLAY_EXPIRED` для удалённого full receipt **только после контрактного review и миграционных тестов**.
- `SceneRouter` сохраняет обратный адрес из любого активного мира через `scene.positions`, `return_scene_id`, `player.hp`; **G и HUD** работают до первого боя и при живом враге, но не снимают внешний pause/recovery lock. `Left Ctrl` открывает радиальное меню, `Right Ctrl` игнорируется; обе функции объединены в один UI в PR #50. Вся UI логика A5, A1 владеет commit.
- `Player.try_attack()` наносит melee урон только при положительной проверке `World2D.direct_space_state.intersect_ray` без перекрывающей физической стены; обычные cooldown/range/facing остаются. Источник — PR #52.
- **Farm/save compatibility:** при поливе новые plot сохраняют `grow_minutes_at_planting` и `spoil_minutes_at_planting` плюс `planted_at/ripe_at/spoil_at`. Старые поля без duration stamps загружаются при последовательных положительных сроках; баланс `rules.crop` используется только для **новых** посадок. Увеличение `rules.version` остаётся явным миграционным gate, а не тихой заменой save. Это проверено CT A0-F01 в PR #51 на Linux/Windows.
- **Sub-minute clock:** `CoreSession.try_accumulate_fractional_clock` изменяет лишь `clock_remainder` пока до следующей календарной минуты менее 1. В это время `state_revision` **не** растёт, events не публикуются и глобальная валидация не гоняется каждый кадр. На границе минуты `CampaignSession.tick` вызывает прежний `apply_runtime` с полной транзакционной проверкой. При следующем durable checkpoint остаток сохраняется в snapshot. Pause/recovery и числовые ограничения остаются обязательными.
- **EventBus:** история доставки уведомлений ограничена `HISTORY_LIMIT=4096` recent IDs. Старые уже выпавшие IDs могут быть заново *уведомлены*, но не должны начислять ресурсы/награды. **Единственный** источник exactly-once для мутаций — `completed_actions` и доменные уникальные `claimed_reward_ids`. `reset_history()` сбрасывает transient ring при загрузке, не persistent receipts.
- **Persistent receipts:** журнал сейчас **неограничен**. Это сознательно оставленный открытый риск A0-F05, потому что произвольные action_id и exact replay без другого долговременного proof исключают безопасное безусловное удаление старых записей. Профиль 100/1k/10k receipt sizes нужен до выбора migration/compaction policy; ни один PR не должен удалять записи наград наугад.

### 17.2 Статус валидации и незакрытые решения

| Область | Подтверждённое свидетельство | Что НЕ доказано |
|---|---|---|
| PR #50 HUD + shelter | Linux/Windows CI, real visual и совместные E2E на одном SHA `44c337baa...` | ручная проверка GUI на ПК, независимые A1/A2/A5/A0 |
| PR #51 crop/save | Linux+Windows с семью дополнительными legacy/rebalance тестами, SHA `b60b9972...` | версионированная миграция всего ruleset и старой экономики |
| PR #52 wall LOS | Linux+Windows, реальная physics wall regression, SHA `6399081e...` | полная сценарная проверка всех видов препятствий/оружия |
| PR #53 tick/dedup | Linux+Windows CI, 50 subminute frames, 100k event IDs; SHA `3e0f567d...` | длительный Windows GPU profiler, безопасная компакция receipts |
| G0/G4 | Требования и code candidates присутствуют | обязательные независимые ревью, owner-approved exact SHA, ручной UX 15–35 минут |

**Нормативный статус остаётся `v1.6-PROPOSED` / G0_BLOCKED.** Перед заморозкой A1 подтверждает DTO/API/migration, A2 — боевой ray/ввод, A3 — crop/calendar, A4 — NPC/quests, A5 — единый HUD/паузы/UX, A0 сверяет риски. После этого владелец проекта отдельно подтверждает точный commit SHA и только тогда допускается `G0_APPROVED`; ни один автоматический тест не является подписью владельца.

# 05 — Единый контракт модулей, состояния и сохранений

**Контракт:** `v1.0-CANDIDATE` · **Технический редактор:** A1 · **Архитектурная координация:** A5 · **Независимая сверка:** A0 · **Статус:** G0 review required, **не рабочий API**. **ЭТО ЕДИНСТВЕННЫЙ НОРМАТИВНЫЙ КАНДИДАТ КОНТРАКТА**: прежняя редакция 05 и черновик 07 из PR #5 заменяются этой версией. [G0](08-g0-decision-record.md), [архитектура](06-application-architecture-proposal.md).

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

CommandRequest := {
  action_id: ActionId,
  command_type: StringName,
  context: { scene_id, actor_id, expected_state_revision? },
  payload: Dictionary
}
CommandResult := {
  ok: bool, code: ErrorCode, action_id: ActionId,
  state_revision: int, data: Dictionary, message_key: String
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

**Повтор команды:** тот же `action_id` + тот же fingerprint запроса возвращает записанный результат, без мутаций; тот же `action_id` + другой payload/контекст → `ACTION_CONFLICT`. Новый игровой клик, сознательно создающий новую покупку, получает новый `action_id`; UI не должен путать его с повторной доставкой одного клика. Для предотвращения однократных сюжетных наград дополнительно проверять устойчивый `reward_id`/ `enemy_id`, а не только `action_id`.

## 3. Публичные фасады и владельцы

| Фасад | Владелец | Команды / запросы (псевдосигнатуры до реального type-check) |
|---|---|---|
| `GameSession` | A1 | `new_campaign(seed?)`, `get_snapshot()->CampaignSnapshot`, `set_pause(bool)` |
| `GameCoordinator` | A1 | `execute(request:CommandRequest)->CommandResult`; сериализация, validation, commit, notifications |
| `SceneRouter` | A1 | `try_transition(action_id,destination_scene_id,entry_point_id)` |
| `GameClock` | A1 | `get_game_minute()->int`, `try_rest_until(action_id,target_minute,context)`, `advance_for_test(minutes)` **QA-only** |
| `InventoryService` | A1 | `try_transfer(action_id,instance_id,from,to,quantity)`, `try_spend_and_grant(action_id,offer_id)`, `try_claim_parcel(action_id,parcel_id)` |
| `ProgressionService` | A1 | `apply_combat_reward_once(action_id,combat_receipt)`, `register_first_item_type(action_id,type_id)` |
| `FarmService` | A3 | `try_till/plant/water/harvest(action_id,plot_id,...)`, `plan_time_advance(from,to)` |
| `CombatService` | A2 | `resolve_attack(attack_id,attacker,target,weapon)`, `get_combat_snapshot()` |
| `ResidentService` | A4 | `try_accept_contract(action_id,resident_id,version)`, `plan_recruitment(action_id,resident_ids,food_rule_id)`, `try_assign_job(action_id,resident_id,job_id)` |
| `QuestService` | A4 | `get_active_quests()`, `plan_quest_progress(tentative_state)` |
| `UILayer/ViewModels` | **A5** | `render_snapshot()`; UI triggers commands and displays `message_key`; **does not mutate game data** |

Кандидат версий контрактов должен быть подтверждён ревью **A1–A5**, A0 выполняет независимую трассировку и ревью UI. Реальные GDScript имена/типы проверяются при bootstrap G1a без произвольного изменения внешних гарантий.

## 4. Инварианты и транзакции

1. **Одна операция — один эффект.** Нельзя выдавать награду, XP, посылку, жителей или создавать урожай дважды при повторе, reload или двойной подписке.
2. **Состояние меняет владелец через coordinator:** A2 — подтверждение попадания/смерти, A3 — поле/постройка, A4 — согласие/квест. A1 — XP, кошелёк, инвентарь, квитанции, единое состояние и commit. **Не делать доменную запись в EventBus listener.**
3. **Cross-domain action** (сбор→инвентарь; еда→житель; покупка→предмет; убийство→XP/квест) имеет единый validate/plan/commit. Невозможно частично списать еду и не заселить NPC; ошибка переполнения не может «убрать» урожай.
4. **Ревизия UI:** устаревшая команда возвращает `STALE_REVISION` и обновляет snapshot, не применяя изменение поверх чужого состояния.
5. **Отрицательные значения:** количество, деньги, прогресс и таймеры валидируются; есть ID типов и экземпляров, не используем отображаемое имя как ключ.
6. **Одноразовые награды:** сериализуются `claimed_parcel_ids`, `discovered_item_type_ids`, `completed_actions`, `recruited_resident_ids`, `reward_ids`, применённые задания.

### Протокол commit

```text
execute(request):
  validate request, context, expected revision
  if action_id exists: return old result or ACTION_CONFLICT
  tentative = copy(affected authoritative DTOs)
  domain_owner.validate_and_plan(tentative, request)  # no UI/signal side-effects
  coordinator.assert_invariants(tentative)
  if invalid: return error (no mutation)
  if durable action: persist full coherent checkpoint + receipt or return SAVE_FAILED
  publish tentative as new authoritative revision
  enqueue DomainEvent(s) after commit
  return CommandResult + receipt
```

Здесь `durable action` — критичная одноразовая покупка/награда/заселение/посылка и явный save. Другие действия могут сохраняться по разумному автосейву, но **не** показывать недостоверного подтверждения устойчивого сохранения. G1a/реализация обязаны разрешить порядок атомарной смены файла и памяти с проверкой на Windows.

## 5. Порядок времени и safe rest

- Авторитетный clock — **целые игровые минуты** `game_time_minutes`. Время активной игры идёт естественно; `minutes_per_real_second` хранится в `game_balance` и не задаётся как закон книги.
- Для каждой культуры `grow_minutes`, `spoil_minutes` находятся в версии правил. Книжный картофель 72/12 игровых часов — **референс**, не неизменяемый hardcode. Тесты используют активное значение конфига, отдельно могут проверять референсную фикстуру.
- Игрок может **безопасно отдыхать** в зоне палатки до ближайшей зрелой культуры или выбранного допустимого времени: UI A5 → команда `GameClock.try_rest_until(...)` A1. При опасности/боевой активности или невозможном deadline → понятный отказ без изменения времени.
- **Один скачок** времени обязан корректно обработать рост/порчу ВСЕХ полей, релевантные deadlines/квесты, дискретные правила и системные уведомления в детерминированном порядке `tentative_clock → domain plan → commit → ordered events`. На больших скачках при интерактивном событии — остановка/предупреждение, а не молчаливое пропускание обязательного выбора.
- `advance_for_test(minutes)` существует **только в QA окружении** и не подключён к обычному UI. Пауза останавливает игровой clock, но не управление меню.

## 6. Запас еды для заселения (без захардкоженных двух картофелин)

```text
arrival_food_requirement := {
  rule_id: String,                  # версия правила баланса
  accepted_food_type_ids: [String],# например crop.potato; список задаёт баланс
  units_per_resident: int >= 0,    # определяется балансом A3/A5
  reserve_mode: "reserve" | "consume"   # P0 предпочтительно reserve
}
```

Конфиг/формула `needed_units = units_per_resident × количество заявленных жителей` — пример общего правила. Более сложная структура допускается через версию `food_rule_id`. **Никаких 2 картофелин как обязательной нормы.** Можно тестировать `units_per_resident = 1` и `3` как фикстуры; это не утверждение реального баланса.

**Поток:** A4 фиксирует информированное добровольное согласие, NPC остаётся `AWAITING_SUPPLIES`; A1 проверяет конфиг и доступный food container; в **одном commit** создаёт уникальный резерв с `reservation_receipt_id`, переводит уникальных NPC в `RECRUITED`, обновляет Q07 и выдаёт награды. Нехватка еды → никакого частичного списания и заселения. Повтор того же action/попытка с другим action после успеха не повторяет эффект; для нескольких NPC в batch — все-or-none, для отдельного человека отдельная транзакция. P0 сохраняет `job_id`, но регулярные голод/труд — P1.

## 7. События P0 после commit

| event_type | Минимальные поля payload | Владелец факта |
|---|---|---|
| `enemy_defeated` | enemy_id, enemy_type_id, weapon_type_id, is_system_weapon | A2 + A1 commit |
| `system_unlocked` | reward_id, skill_id | A1 |
| `scene_changed` | from_scene_id, to_scene_id, return_point_id | A1 |
| `item_transferred` | instance_id, type_id, quantity, from_id, to_id | A1 |
| `first_item_type_discovered` | type_id, xp_awarded | A1 |
| `parcel_claimed` | parcel_id, receipt_id | A1 |
| `time_advanced` | from_minute, to_minute, reason | A1 |
| `crop_stage_changed` | plot_id, old_stage, new_stage | A3 |
| `crop_harvested` | plot_id, type_id, quantity, inventory_receipt_id | A3/A1 |
| `resident_contract_accepted` | resident_id, contract_version | A4 |
| `arrival_food_reserved` | reservation_receipt_id, food_rule_id, quantity | A1 |
| `resident_recruited` | resident_id, reservation_receipt_id | A4/A1 |
| `quest_completed` | quest_id, reward_receipt_id | A4/A1 |
| `state_loaded` | schema_version, state_revision | A1 |

UI A5 переполучает snapshot после `state_loaded`. EventBus listeners отписываются при уничтожении сцены; повторное открытие меню не должно создавать N подписок. Прогресс квеста вычисляется внутри транзакционного плана; event только уведомляет о завершении.

## 8. Сохранение и отказоустойчивость

```json
{
  "schema_version": 1, "ruleset_version": "g0-candidate",
  "save_id": "slot-01", "state_revision": 0, "game_time_minutes": 0,
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
- Harvest на полный инвентарь; отсутствуют семена/вода/монеты/еды; stale snapshot; 0 и 3 единицы `units_per_resident` в тестовых правилах.
- Два разных поля, пересекающиеся deadlines при длинном отдыхе; пауза во время open modal; QA метод недоступен обычной игре.
- Save corrupted/truncated + backup; версия `schema_version` больше известной; двойной вход в сцену и повторное открытие UI.
- Игра остаётся функциональной, если Q03–Q07 не активированы.

Подробно — [10-qa-acceptance-matrix.md](10-qa-acceptance-matrix.md). Без фактического запуска все тесты **NOT_RUN**.

## 10. Изменения и заморозка

Этот контракт **не считается утверждённым до G0**. Breaking change: Issue `[CONTRACT]` + список потребителей + review A1–A5 + A0 по риску, версия, тест/миграция, новая ссылка на SHA. Сама работа над документацией и создание PR не означает разрешения писать Godot-код. Для G0 необходимы доказательства ревью и явное утверждение владельцем **точного commit SHA**.

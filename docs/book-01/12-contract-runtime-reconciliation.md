# 12 — Сверка G0 с фактически реализованным прототипом (08.11.2026)

**Статус:** `REVIEW_PROPOSAL / G0_BLOCKED` · **Целевой код:** [PR #31](https://github.com/AndreyCokol/My_shelter/pull/31), commit `59bb12517e21850386092bd1e0a5e3d79c23c98a`. **Решение владельца о постоянном убежище:** [Issue #37](https://github.com/AndreyCokol/My_shelter/issues/37), кандидат [PR #39](https://github.com/AndreyCokol/My_shelter/pull/39). **Радиальное меню:** кандидат [PR #38](https://github.com/AndreyCokol/My_shelter/pull/38). Это не технический sign-off и не слияние веток.

## 1. Источники истины и границы

1. Принятые решения владельца OD-01..OD-11 в [08](08-g0-decision-record.md), а также **новое** OD-12 — пространственное убежище доступно в любой момент активной игры (Issue #37), имеют приоритет над устаревшим onboarding-ограничением из 03/06/09.
2. **Единственный действующий кандидат технического контракта** — [05-integration-contracts.md](05-integration-contracts.md) `v1.5-PROPOSED` с дополнительной сверкой реализованной schema v4. Исторический `07` из закрытого PR #5 и `05 v1.0` из PR #7 не применять независимо. После review A1/A2/A3/A4/A5 отредактировать **один** 05 и отметить точный SHA.
3. Главная ветка `main` остаётся документационной по проверенному git tree, но унаследованный PR-стек **действительно содержит игровой код** и CI; прежние заметки «код отсутствует» относятся только к `main` или к дате их написания.
4. Область P0 — **15–35 минут свободной песочницы** с коротким обучением и добровольными NPC. Существующие дополнительные 26 процедурных узлов, производство, сети лагерей и фракции — экспериментальные реализации, **не обязательный G4** до принятого scope. Весь пространственный осколок LATER.
5. Роль A5 — главный и **единственный владелец UI**, A1 — владелец core/commit/save, A2/A3/A4 — домены; A0 — независимый reviewer/советник без права утверждать G0. Ни один документ, подписанный только одной сессией, не заменяет review пяти владельцев.

## 2. Разница v1.0 → v1.5 → реальный runtime v4

| Область | PR #7 / контракт v1.0 | PR #31 / контракт v1.5 | Проверка относительно исходников / требуемое действие |
|---|---|---|---|
| Схема | Иллюстративный JSON `schema_version:1`, `campaign-core` без procedural layout | Накоплены дополнения про v2/v3; базовый JSON пример по-прежнему v1 | `CampaignModel.new_state()` создаёт core v2, `Gameplay.seed()` ставит v3, `new_state()` завершается v4 при gameplay; **не использовать** JSON v1 как тестовую фикстуру v4 |
| Сцены | 4 фиксированных ID, позиция вне убежища | scene.positions, entry/return, world seeds/graph | `WorldLayout` поддерживает 26 узлов; `SceneRouter` проводит stage + checkpoint + install. Записать `world_states.layout`, entry registry, `return_scene_id`, `scene.positions` в действующий контракт |
| Миграции | Будущая цепочка `v1→v2` — гипотеза | Существуют отдельные ограничения v2/v3 | `CampaignModel.validate()` допускает v3 как legacy при v4 ruleset, но не обещает полную миграцию всех старых save. Требуется acceptance-фактура по v2/v3/v4, сохранение старого файла при отказе |
| Игровое время | Один clock, отдых, календарь | CalendarPlanner, stateful deadlines, QA | В gameplay v4 два поля/clock deadlines; `GameRules.build().crop.grow_minutes=180`, `spoil_minutes=120`: **дизайн**, а не 72/12 книг. Рецепт в current rules — не универсальный канон |
| Первые жители | Еда положительная и настраиваемая, добровольное согласие | A4 status/consent + inventory receipt | `GameplayState.validate()` сверяет food_receipt; **не закреплять 2 картофелины**. Применить save/backcompat тесты |
| События | Envelope с `event_type`, commit-before-publish | Payload copy, owner-scoped subscribers | `EventBus._seen` пока растёт без лимита; история delivery **не** является persisted ledger |
| Состояние | `completed_actions` + fingerprint | Resource revisions + scoped receipts | `CoreSession.execute()` записывает полный receipt, checkpoint на durable commands; нужен retention/stress policy до длительной песочницы |
| Tick/runtime | Calendar planner как API | Подключён runtime/сцена | `CampaignSession` вызывает `apply_runtime()` на кадрах, `CoreSession.apply_runtime()` дублирует/валидирует состояние; профиль до/после обязателен |
| Доступ в убежище | Онбординг привязывает unlock к первому зомби | До PR #39 runtime `game_app.gd` и `campaign_commands.gd` ограничивают переход первой победой | **OD-12:** вход `G`/HUD до первого зомби и в любом бою; возврат в тот же scene+position+HP, без System reward. В PR #39 кандидат реализации, не выдавать за объединённый с PR #31 |
| HUD | Полный UI A5, modals + pause tokens | UI A5 с asset theme, `640×360` design viewport | PR #38 добавляет radial left Ctrl + HUD; PR #39 добавляет Shelter quick action. Файлы `game_app.gd`, `game_ui.gd`, `README.md` перекрываются; нужен отдельный **интеграционный PR**, где обе функции сохранятся |
| Версия движка | Baseline Godot 4.7.2-stable | Реальное CI на Godot 4.7.2 в PR #31 | PR #38 body упоминает Godot 4.6.3; сравнивать **лог исполняемого workflow** с описанием перед merge, не выводить из названия задачи |

**Кодовые якоря:** [CampaignModel](../../game/state/campaign_model.gd), [GameplayState](../../game/state/gameplay_state.gd), [GameRules](../../game/data/game_rules.gd), [CoreSession](../../game/systems/core/core_session.gd), [EventBus](../../game/systems/core/event_bus.gd), [CampaignCommands](../../game/systems/inventory/campaign_commands.gd), [GameApp](../../game/app/game_app.gd), [SceneRouter](../../game/systems/scene_router/scene_router.gd). Все ссылки в этой ветке указывают на исходники PR #31; смежные #38/#39 проверяются по собственным head SHA.

## 3. Критические неурегулированные риски

### R-01 — открытые дефекты A0, не подменять успехом CI

- **[Issue #34](https://github.com/AndreyCokol/My_shelter/issues/34):** `GameplayState.validate()` требует `ripe_at=planted_at+rules.crop.grow_minutes`, `spoil_at=ripe_at+rules.crop.spoil_minutes`. Изменение рецепта ломает старые growing-save, даже если `ruleset_version` не меняется. Решение A1/A3: persist duration per plot *или* versioned migration, тест old config→new config; опасно переписать правило без миграции.
- **[Issue #33](https://github.com/AndreyCokol/My_shelter/issues/33):** ближняя атака через стену — смотреть `player.gd` и коллизии уровня, нужен physics line-of-sight. A2 и A0 должны подтвердить на мире с препятствием.
- **[Issue #35](https://github.com/AndreyCokol/My_shelter/issues/35):** per-frame full clone+validate, unbounded `EventBus._seen`, потенциальный рост `completed_actions`. Это **кодово наблюдаемые операции, но без stress/profiler — не доказанный FPS defect**. Требуются измерения 26 локаций и 100/1000/10000 receipts, 100k event IDs, 10k команд с сохранением. Не удалять одноразовые receipts без стратегии.
- **[Issue #14](https://github.com/AndreyCokol/My_shelter/issues/14):** личный **закрытый** прототип не означает, что public repository сам стал private. Не публиковать сторонние материалы с неясной лицензией.

### R-02 — текущие UI-ветки требуют совместной интеграции

Проверено через сравнение base PR #31 с #38/#39: пересекаются `README.md`, `game/app/game_app.gd`, `game/ui/game_ui.gd`. Нужен новый интеграционный PR поверх **одного** из них, ручной перенос второй функции и регрессионные тесты; две независимые merge-попытки без проверки отклонить.

**Контроль на объединённом head:**
1. `Left Ctrl` открывает/закрывает radial; `Right Ctrl` не открывает его.
2. `G`/HUD shelter работает до Q01, из боя и из всех сцен; из убежища возвращает на точную исходную точку.
3. Из открытого modal/radial переход освобождает **только свой** pause token; внешний recovery/critical pause не обходится.
4. Любые ошибки сохранения → не перемещать героя, не выдавать награды, не терять HP/позицию.
5. В HUD и modal элементы укладываются в `640×360`; `run_asset_tests.gd` и UI render checks должны быть зелёными.
6. После полного exit/restart сохраняются locations, seed, world state, HP, inventories, quests и return point.
7. Измерить взаимодействие Q01/tutorial/UI: открытие убежища до победы не разблокирует магазин/посылки/системные награды.

### R-03 — доказательство CI на точном SHA

- На PR #31 head `59bb125...` core/Windows/documentation проверены успешно: [core](https://github.com/AndreyCokol/My_shelter/actions/runs/42398323237), [Windows](https://github.com/AndreyCokol/My_shelter/actions/runs/42398323238). Изменение HEAD после проверки **обнуляет** доказательство относительно нового SHA до нового CI.
- На PR #38 head `da663506...` core/Windows/documentation успешны 08.11; необходимо проверить, что версии движка совпадают с baseline 4.7.2, и не принимать самоописание PR без логов.
- На **первой ревизии** PR #39 `412bf00...` core и Windows failed: по логам **2 ошибки UI geometry**, `navigation icon fits viewport without covering world` и `skinned modal fits design viewport`. Это тестовое несоответствие, не ошибочная логика переходов. PR #39 уже редактировался после указанного failed SHA — новую ревизию проверять заново; **не** фиксировать старое падение как вечный статус ветки.
- Native Windows headless export не заменяет ручной GUI запуск в Windows, 60 FPS benchmark и 15–35 минут независимого пользователя. Для G4 нужны отдельные данные.

## 4. Матрица приёмки изменений после 08.11

| ID | Проверка | Ответственный |
|---|---|---|
| CT-G0-01 | v1.0 vs v1.5 vs schema v4: все persistent поля и команды связаны с реальным файлом/методом; устранены некорректные примеры v1 | A1 + A5, review A0 |
| CT-G0-02 | old save при changed grow/spoil rules загружается безопасно или отклоняется без перезаписи/потери, результат документирован | A1/A3 |
| CT-G0-03 | 2 ветки UI собраны; left Ctrl/radial и G/shelter обе доступны, нет повторных обработчиков ввода | A5/A1/A0 |
| CT-G0-04 | pre-Q01 G → shelter → hospital same position/HP, при этом reward/status unchanged | A1/A2/A5 |
| CT-G0-05 | UI quick-button и modal в 640×360 не выходят за границы, Linux+Windows asset suites PASS на общем SHA | A5 |
| CT-G0-06 | Recover after failed durable transition и external pause; никакого partial commit | A1/A5/A0 |
| CT-G0-07 | Collision/LOS attack blocked by wall; no XP after fleeing | A2/A0 |
| CT-G0-08 | Один игровой clock, no duplicate crop after rest+save+load, deadlines persisted under balance version | A3/A1 |
| CT-G0-09 | UI ownership A5; API mutation only through A1 command envelope, snapshots are defensive copies | A5/A1 |
| CT-G0-10 | Нагрузочные профили: 26 мест, 100/1k/10k receipts, 100k event IDs; отчёт абсолютных чисел памяти/мс | A1/A5/A0 |
| CT-G0-11 | G4 UX: 15–35 min guided/unassisted flow on actual Windows GUI, результаты честно записаны | A5 |
| CT-G0-12 | Public-repo license audit + разрешённый список ресурсов, **без** незаявленного public release | A5 + владелец |

**У каждого теста обязательны:** PR/commit SHA, OS, версия Godot, точная команда, expected/actual, evidence URL и статус `PASS/FAIL/NOT_RUN/SKIP`. Проведённый здесь статический анализ **не создаёт PASS для новых CT**.

## 5. Формальное ревью и критерии freeze

| Роль | Проверить прежде всего | Граница полномочий | Статус независимой подписи |
|---|---|---|---|
| A1 | Команды, план транзакции, persistence, schema compatibility, recovery, resource revision, runtime perf | Core/Save/contract editor | `REVIEW_PENDING` |
| A2 | Combat/LOS, input arbitration, pre-Q01 escape, cancel enemy AI on scene exit | Combat/Player | `REVIEW_PENDING` |
| A3 | Crop duration migration, farming deadlines/QA rest, reservable food units | Farm/Shelter | `REVIEW_PENDING` |
| A4 | Q01–Q07 необязательные, voluntary NPC, food receipt, absence of shard | Quests/Residents | `REVIEW_PENDING` |
| A5 | Chief coordination, весь HUD + radial + shelter modal, pause/focus, accessibility 640×360, Windows UX | UI + cross-module integration | `REVIEW_PENDING` |
| A0 | Независимые Findings A0-F01..F05, стеновые атаки, память, UI PR #38/#39, объективная повторная сверка | Review/advice only | `REVIEW_PENDING` |

Существующий [Issue #4](https://github.com/AndreyCokol/My_shelter/issues/4) остаётся `BLOCKED`, пока нет пяти **реальных** ссылок на ревью и явного owner approval точных SHA SRS/плана/контракта/архитектуры. Правки, тесты и документация одной сессии НЕ являются шестью независимыми ревью.

## 6. Безопасный порядок интеграции

1. Согласовать **принятые** OD-01..OD-12 и технические подробности на одном актуальном commit PR #31 (не переспрашивать владельца о концепции).
2. Принять техническое исправление PR #39 после зелёного CI и независимого A1/A2/A5/A0 просмотра.
3. Интегрировать PR #38 в объединённую ветку, вручную сохранить новый HUD/radial и новый Shelter portal; объединённая ветка обязана пройти Linux/Windows + реальные screenshot checks.
4. После исправления A0-F01/F02 и завершения contract review обновить **только** нормативный `05` до следующего кандидата (например `v1.6-CANDIDATE`) с чёткой моделью schema v4 и миграцией. Старую `07` не восстанавливать.
5. Получить независимые comments/PR approvals A1–A5 и A0 review (где он реально выполнен), подписать точный SHA G0 владельцем и только затем отметить Gate `APPROVED`. Уже существующие игровые PR остаются исторически проверяемыми; G0 не утверждать задним числом автоматически.

**Итог аудита 08.11:** концепция и основные домены достаточно определены; **полной архитектурной приёмки нет** из-за несогласованного v4 save/контракта, двух веток UI, открытых A0 findings, отсутствия формальных отзывов и owner-approved SHA. Это ограничение подтверждается git-ветками, кодом и CI, а не домыслом.

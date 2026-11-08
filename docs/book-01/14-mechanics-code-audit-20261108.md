# 14 — Строгий аудит ВСЕХ игровых механик и реестр дефектов

**Дата:** 08.11.2026 · **Роль:** A0, независимый статический сверщик и советник A5 · **Baseline:** [PR #58](https://github.com/AndreyCokol/My_shelter/pull/58) commit `19c250ea5d1e729230d1535eaf7da7659f7cccc2`. Аудированы фактические исходники GDScript, тесты, контракт, PR #50–58, результаты CI. **Этим аудитом Godot локально не запускался.** `main` всё ещё не содержит эту игровую ветку. [Linux CI](https://github.com/AndreyCokol/My_shelter/actions/runs/42496368375) — 489 Godot + 28 render PASS; [Windows CI](https://github.com/AndreyCokol/My_shelter/actions/runs/42496368349) — 489 Godot + headless export PASS; [docs](https://github.com/AndreyCokol/My_shelter/actions/runs/42496368310) — 18 static contracts PASS. **Ни один из этих прогонов не покрывает автоматически все новые случаи ниже.**

## Методика и значения статусов

- `PASS_EXISTING_TEST` — виден конкретный тест и его зелёный CI на проверенном SHA; **не** ручная приёмка.
- `CONFIRMED_CODE_DEFECT` — исходники прямо содержат несоответствие между валидатором/операцией/требованием; ожидаемое поведение логически выводимо, но новый минимальный запуск ещё **NOT_RUN**.
- `MISSING_FUNCTIONALITY` — требование есть, исполняемой механики нет либо реализована только часть.
- `DESIGN_UNRESOLVED` — код определяет поведение, но выбранная семантика не зафиксирована владельцем/спекой; **не выдавать за подтверждённый crash**.
- `TEST_GAP` — реализация выглядит правдоподобно, но необходимые негативные/GUI/длительные испытания отсутствуют.
- `KNOWN_RISK` — риск уже признан и частично исправлен в отдельном PR, но ещё не закрыт на проверяемой интеграционной базе.

## 1. Матрица покрытия по механикам

| № | Механика / требование | Реальный результат проверки | Статус | Владелец |
|---|---|---|---|---|
| M01 | Песочница, свободная игра после Q02, optional Q03–Q07 | `Gameplay.refresh_quests`, `game.quest_track`, tests без активных Q03–Q07; свобода не заменяет проверку UX | PASS_EXISTING_TEST + TEST_GAP | A4/A5 |
| M02 | Обучение Q01/Q02 и открытие Системы | Первая победа открывает System, G доступна раньше; **Q02 всё ещё названа «Открыть убежище»** | CONFIRMED_CODE_DEFECT F10 | A4/A5 |
| M03 | Топ-даун 90°, камера, управление WASD/стрелки | `player.gd`, `game_app.gd`, `world.gd` и camera; GUI на реальном ПК не проверялся | PASS_EXISTING_TEST + TEST_GAP | A2/A5 |
| M04 | Бой: атака/урон/уклонение, коллизии | `player.gd` проверяет LOS, dodge cooldown; PR #52 physics test PASS, но поведение противников при отступлении не определено | PASS_EXISTING_TEST + DESIGN_UNRESOLVED F08 | A2 |
| M05 | Враги: обнаружение, преследование, смерть | `enemy.gd` ray LOS при патруле, прямое движение к цели, `world.bind` создаёт нового врага при входе; частичные HP/агро не сериализуются | DESIGN_UNRESOLVED F08 + TEST_GAP | A2/A1 |
| M06 | Оружие, экипировка, уровни | В каталоге есть нож, но `player.gd` наносит фиксированные 25 урона; нет equipped weapon/уровней/навыков в state | MISSING_FUNCTIONALITY F07 | A2/A1/A5 |
| M07 | Убежище доступно всегда | `G`, кнопка HUD/меню, до Q01 и во время боя; возврат из квартиры/верхнего этажа и сохранение позиции/HP проверены | PASS_EXISTING_TEST; GUI NOT_RUN | A1/A5/A0 |
| M08 | Смерть и безопасное восстановление | `game.player_defeated` сохраняет возрождение, но использует **жёсткую точку 120×260** в hospital/shelter, не «последнюю безопасную»; проверить геометрию и return state | DESIGN_UNRESOLVED F11 | A2/A1 |
| M09 | Процедурные улицы/дома/16 этажей больниц | 128 seed, graph/door/room tests, 26+ nodes, графовые маршруты и физическое движение одной квартиры; исчерпывающая GUI проверка дверей на всех seed отсутствует | PASS_EXISTING_TEST + TEST_GAP F12 | A2/A5 |
| M10 | Ресурсы, тайники, лут, обновление | `game.resource_collect` и hospital cache сохраняют cooldown/looted, есть negative tests; ресурс недоступен до первой победы — сценарное условие требует явного объяснения | PASS_EXISTING_TEST + DESIGN_UNRESOLVED F13 | A2/A4 |
| M11 | Две атмосферы мира | `world_art.gd` разделяет холодный город и тёплое убежище; нужные детализированные анимации персонажей не подключены | PARTIAL + MISSING_FUNCTIONALITY F14 | A5/A2 |
| M12 | Ферма: посев, полив, рост, порча, сбор | `game.plant/water/harvest/clear`, `GameplayCalendar`; PR #51 устранил crop rebalance; tests PASS | PASS_EXISTING_TEST | A3/A1 |
| M13 | Естественное время, отдых, дедлайны | Один `CalendarPlanner`; tests таймингов, пауз/rollback PASS; полный clone+validate на каждом frame tick в PR #58 | KNOWN_RISK F15 | A1 |
| M14 | Инвентарь, вместимость, резервы | `CampaignCommands`, `Gameplay.available`, UI transfer; tests переполнения, reload/replay; UI пока переводит только весь свободный стек | PASS_EXISTING_TEST + UX_GAP F16 | A1/A5 |
| M15 | Системный магазин, посылки, монеты | Domain transactions динамичны по `rules.offers`, но текст магазина показывает фиксированные 2 семени/3 монеты | CONFIRMED_CODE_DEFECT F10 | A1/A5 |
| M16 | Поселение NPC, согласие, пища | Consent/recruit/reserve/consume tests PASS на разных правилах; **старые квитанции сверяются с новым балансом еды** | CONFIRMED_CODE_DEFECT F06 (BLOCKER) | A1/A3/A4 |
| M17 | Работа жителей и отдых на кровати | Смены, сроки, результаты в коде и тестах; затраты всегда `crop.potato`, несмотря на альтернативную еду | CONFIRMED_CODE_DEFECT F09 | A3/A4 |
| M18 | Строительство, шкафы, кровати, верстак | Функции построек/демонтажа/ремесла, тесты объёма склада; свободная физическая проходимость после строительных комбинаций недостаточно проверена | PASS_EXISTING_TEST + TEST_GAP F17 | A3/A2/A5 |
| M19 | Сюжетные NPC, задачи, диалоги | Q01–Q07, контакты и согласие работают; живой диалог пока представлен несколькими статичными строками; отложенные взрослые темы не перенесены | PARTIAL + UX_GAP | A4/A5 |
| M20 | Районные события, экспедиции, торговля | `district_events`, `expedition_order`, `camp_network`; тесты callback/reward; правила времени торговли и события вне окна нуждаются в проверке | PASS_EXISTING_TEST + TEST_GAP F18 | A4/A1 |
| M21 | HUD, радиальное левый Ctrl, G, модальные окна | PR #50 объединяет ввод и pause ownership; 28 render checks PASS, GUI на ПК НЕ проведён | PASS_EXISTING_TEST + TEST_GAP | A5/A0 |
| M22 | Сохранения, загрузка, миграции | `CheckpointStore` temp/backup, schema4, PR #51 crop fix; **resident food rule rebalance ломает старый save**; full schema/ruleset migration не реализована | CONFIRMED_CODE_DEFECT F06 + KNOWN_RISK | A1 |
| M23 | Перезапуск игры и безопасная новая игра | `GameApp.new_game` архивирует slot и переинициализирует сцену; нужен тест существующего save, новой игры с другим seed и отката ошибки архива | TEST_GAP F19 | A1/A5 |
| M24 | Производительность, FPS, память, idempotency ledger | PR #58 ограничил EventBus 4096 IDs; full clone на кадр и `completed_actions` не ограничены; PR #53 другой вариант оптимизации **не интегрирован** в #58 | KNOWN_RISK F15/F20 | A1/A0 |
| M25 | Windows x64/offline/лицензии | CI native Windows export/headless PASS, Kibyra 18 textures included; manual GUI, license ZIP HappyHustle и PRIVATE delivery НЕ проверены | TEST_GAP | A5/A0/владелец |

## 2. Подтверждённые дефекты и функциональные недоделки

| Код | Приоритет | Факт из конкретного кода | Сценарий/необходимое исправление | Ответственный |
|---|---|---|---|---|
| **F06** | **BLOCKER P0** | `game/state/gameplay_state.gd:83–95` сравнивает сохранённую food receipt жителя с **текущими** `rules.food`; `gameplay_commands.gd:320–348` записывает исходный состав | Заселить при 2 ед. reserve, сохранить, изменить баланс на 3 или consume, загрузить. Старый NPC и резерв должны остаться действительными через иммутабельную квитанцию/миграцию. [Issue #61](https://github.com/AndreyCokol/My_shelter/issues/61) | A1+A3+A4 |
| **F07** | **MAJOR P0** | `game/entities/player/player.gd:55–75` наносит постоянный урон 25, игнорируя `tool.basic`; нет `equipped_item_id`, `level` или прокачки в `CampaignModel` | Сравнить бой без оружия и с ножом; экипировка/характеристики должны влиять на бой. По уровням — зафиксировать P0 или перенос в P1. [Issue #62](https://github.com/AndreyCokol/My_shelter/issues/62) | A2+A1+A5 |
| **F09** | **MAJOR P1** | `game/systems/shelter/resident_work.gd:6` использует `FOOD="crop.potato"`, независимо от `GameRules.food.accepted_food_type_ids` | Заселить при альтернативной разрешённой еде и попытаться назначить работу. Конфиг должен различать оплату труда/рацион или использовать общий допустимый рацион. [Issue #64](https://github.com/AndreyCokol/My_shelter/issues/64) | A3+A4 |
| **F10** | **MAJOR UX P0** | `game/ui/game_ui.gd:13`: Q02 «Открыть убежище», хотя G доступна до Q01; `game_ui.gd:495–497`: магазин показывает фиксированные 2 семени/3 монеты | Исправить сюжетный текст и отображать цену/количество из текущего `rules.offers`. Проверить GUI при другом балансе. [Issue #65](https://github.com/AndreyCokol/My_shelter/issues/65) | A5+A4 |
| **F14** | **Недостающий art scope** | `game/entities/player/player.gd:_draw` и `enemy.gd:_draw` рисуют примитивные фигуры, без `AnimatedSprite2D`/64×64 move/attack loops | Ввести оригинальные/лицензированные игровые spritesheets и направленные анимации, сохраняя top-down 90°; до этого нельзя считать 64×64 анимации реализованными | A5+A2 |

**Значение «подтверждено»:** код однозначно содержит указанное свойство и противоречие. Отдельный запуск минимального нового бага **НЕ выполнен**; тесты CT-53.. необходимо добавить, а не помечать задним числом PASS.

## 3. Риски и вопросы, которые ещё нужно воспроизвести

| Код | Приоритет | Наблюдение и источник | Как проверить / решение |
|---|---|---|---|
| **F08** | **MAJOR — design & combat risk** | `game/scenes/worlds/world.gd:124–142` создаёт нового врага с 100 HP при возвращении, если `defeated=false`. Частичные HP/агро/таймеры не сериализованы | [#63](https://github.com/AndreyCokol/My_shelter/issues/63): урон по врагу→G→возврат→сравнить HP; смертельный удар→G в том же кадре→проверить одноразовую награду. Решить: сохранять encounter либо явно восстанавливать его без эксплойта |
| **F11** | **MAJOR — требования checkpoint** | `gameplay_commands.gd:139–146`: поражение переносит к жёсткой позиции `(120,260)` в больнице или убежище, а не к сохранённому «последнему безопасному» checkpoint | Пройти этаж/квартиру, умереть, проверить безопасную точку и спавн относительно стен/построек; согласовать семантику с A2/A5 |
| **F12** | MAJOR — geometry proof | WorldLayout + BuildingPlan проверяют связи/якоря, отдельные физические проходы; ручная проверка всех связных квартир, дверей и лестниц на многочисленных seed НЕ проведена | Тест физического пути с коллизией героя (r=9), прерывание дверей, fallback, визуальные скриншоты типовых этажей и мест после save/load |
| **F13** | Owner clarification | `gameplay_commands.gd:148–149` запрещает **все** `game.*` до первой победы. При этом G в убежище работает до Q01 | Решить, разрешены ли до победы действия грядок/хозяйства. Требование владельца «всегда можно уйти» выполнено, но «можно всегда фермерствовать» в этом же состоянии **не утверждено** |
| **F15** | MAJOR performance risk | PR #58: `CampaignSession.tick` вызывает `CoreSession.apply_runtime` с deep-copy/validate на каждом кадре даже без календарной минуты | [Issue #35](https://github.com/AndreyCokol/My_shelter/issues/35), [PR #53](https://github.com/AndreyCokol/My_shelter/pull/53) предлагает fractional fast-path отдельно, **не в PR #58**. Нужен профиль по 1k/10k receipts и сравнение на общем SHA |
| **F16** | MINOR usability | UI инвентаря (`game_ui.gd:604–608`) переносит весь доступный стек, хотя core умеет `quantity < available` | Проверить необходимость частичного переноса для реальной хозяйственной игры. Добавить кнопки/числовое поле по решению A5 |
| **F17** | MAJOR geometry test gap | `game.build` проверяет текущую позицию героя и занятость клетки, но не достижимость дверей, поля и других объектов после установки нескольких построек | Комбинации всех 10 ячеек, проверка реального пути от входа ко всем обязательным точкам и возврату; если блокирует — отклонять строительство либо сделать проходной объект |
| **F18** | MINOR specification ambiguity | `game.trade_camp` проверяет reputation и last_trade, но не `Camp.schedule(...).active`; временной интервал 06–18 применяется к контракту, не к торговле | Решить, открыта ли торговля вне окна контрактов. Проверить на 00:00, 05:59, 06:00, 17:59, 18:00 |
| **F19** | MAJOR regression gap | `GameApp.new_game` архивирует файлы до решения `fresh`/reload; нет явного полного теста сброса слота после ошибки переименования/перезагрузки | Запуск с существующим save+bak, новый seed, ошибка архива, reload fail, повтор New Game, загрузка архива; доказать сохранность предыдущих файлов |
| **F20** | MAJOR long-session risk | `CoreSession.execute:156` добавляет к каждому действию полный result в `completed_actions`; сериализация сохраняет весь ledger | [Issue #35](https://github.com/AndreyCokol/My_shelter/issues/35); [PR #56](https://github.com/AndreyCokol/My_shelter/pull/56) имеет synthetic 10k receipt benchmark в альтернативной ветке. Не удалять квитанции без exactly-once гарантий |
| **F21** | MAJOR AI test gap | `enemy.gd:48–60` двигается напрямую к цели/патрульной точке через `velocity`, без navigation path вокруг стен | Spawn врага и игрока по разные стороны нескольких комнат/углов, проверить path reachability и застревание на StaticBody2D; снять лог траектории и кадры |
| **F22** | MINOR/MAJOR input test gap | `main.gd:6–22` добавляет InputMap события при каждом `_ready`, без явного очистки/проверки дублей | 20 раз New Game/scene reload, сравнить `InputMap.action_get_events` и фактическое число command invocations на один ввод; не заявлять дубли до теста |
| **F23** | MAJOR delivery gate | [Issue #14](https://github.com/AndreyCokol/My_shelter/issues/14): репозиторий PUBLIC, игра PRIVATE_ONLY; в старом плане HappyHustle ZIP/license не проверены | Принять стратегию доступа, проверить каждый asset license, ручной Windows GUI/offline/15–35 minutes; НЕ считать EXE headless публичным/готовым релизом |

## 4. Порядок устранения до следующей приёмки

| Очередь | Обязательное действие | Доказательство приёмки |
|---|---|---|
| **A0-1** | **F06** — защищённая миграция/отвязка resident receipts от нового food rule | CT-53..56, старые save после смены конфигурации, Linux/Windows |
| **A0-2** | **F07** — боевое оружие в реальном состоянии или согласованный сокращённый P0 scope | CT-57/58, переэкипировка, урон, save/load |
| **A0-3** | **F08** — определить и проверить состояние врагов при бегстве по G | CT-59/60, отсутствие double-reward |
| **A0-4 (P1)** | **F09** — работа жителей при альтернативной еде и резервах | CT-61/62, отказ при полном резерве и правильное списание |
| **A0-5** | **F10** — актуальные тексты квеста/динамические данные магазина | CT-63/64, GUI screenshot |
| **A0-6** | F11, F17, F21, F22 — физическая геометрия/AI/чекпойнты/долгий InputMap | CT-65..70, точные seed, репродукция |
| **A0-7** | F15/F20 — объединить оценённый performance path PR #53/56 с PR #58 без дублированного EventBus | 100/1000/10000 receipts, длительность кадра/память на Windows, без нарушения rollback |
| **A0-8** | F14, F23 и общий UX — визуальные персонажи/лицензии/закрытая Windows GUI приёмка | реальные screenshots/recordings, 15–35 минут, лицензии |

## 5. Правила принятия исправлений

Каждый дефект получает Issue/PR, `owner`, `severity`, исходный SHA, точные `file:line`, шаги воспроизведения и негативный автотест. **Не** делать перепроектирование всех модулей: исправить конкретный инвариант в зоне A1/A2/A3/A4, UI делает только A5. A0 проводит независимое code/vertical review, не мержит или утверждает собственный PR. `PASS_EXISTING_TEST` не означает `ISSUE_CLOSED`, пока не выполнены новые CT и требуемый GUI/UX.

**Общий статус:** `AUDIT_DOC_COMPLETE / HIGH_RISK_FINDINGS_OPEN / NEW_REGRESSIONS_NOT_RUN / G0_BLOCKED / G4_NOT_ACCEPTED`. Доступ в убежище OD-12 остаётся безусловным; нельзя «исправлять» этот инвариант введением кулдауна/сюжетного gate.

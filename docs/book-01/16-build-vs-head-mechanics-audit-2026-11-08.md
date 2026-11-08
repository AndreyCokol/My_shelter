# Аудит игровых механик: выданная Windows-сборка vs актуальный интеграционный код — 08.11.2026

**Роль:** независимая техническая сверка / A0. **Статус:** `AUDIT_ONLY / NO_GAMEPLAY_CODE_CHANGED / G0_REVIEW_PENDING`.

## 0. Критически важные сведения о версии

- **Переданный пользователю файл** `MyShelter-Windows-x64-preview.zip` — ZIP, 2 файла (`MyShelter.exe` 110 044 552 байт и README). SHA256 ZIP: `0fefbe2c003132cabfb5989ad0f6accf0effcc0fab426d91ba954dee60893fd6`; в README внутри ZIP зафиксирован **source SHA `1ea01bdf5909fc118d7d585f32de8f8f9e6e2887`** из [PR #83](https://github.com/AndreyCokol/My_shelter/pull/83).
- **Более новая интеграционная ветка** [PR #93](https://github.com/AndreyCokol/My_shelter/pull/93), `db10a24db888b0a62c81f85229f67e8233bc46aa`. Сравнение GitHub: **ahead by 11 commits** относительно версии переданного EXE (без расхождения назад), **18 изменённых файлов**.
- Новые коммиты содержат **фикс оплаты смен жителей любыми разрешёнными пищевыми продуктами** ([PR #88](https://github.com/AndreyCokol/My_shelter/pull/88)), улучшенные **checkpoint/backup/recovery и автосохранение HP/позиции** (перенос из [PR #92](https://github.com/AndreyCokol/My_shelter/pull/92)), дополнительные отрицательные тесты.
- **НЕ НАЗЫВАТЬ** переданный EXE «последней исправленной версией»: он **не включает** код PR #93. Само наличие обновлений после EXE не доказывает, что пользователь воспроизвёл ошибку; оно доказывает отличие сборки от текущего кандидата.
- Все перечисленные PR являются `draft/open` и **не заменяют содержимое `main`**. Факт успешного CI ветки не равен owner G0/G4 acceptance.

## 1. Что действительно было протестировано

На **точном SHA PR #93** GitHub Actions завершились `success`:
- [Linux Godot core bootstrap, run 42508806590](https://github.com/AndreyCokol/My_shelter/actions/runs/42508806590): **1 742 domain/core/gameplay/world/layout assertions / 0 failures** (сумма именованных suite counts), отдельно **28 реальных software-rendered visual checks / 0 failures**.
- [Native Windows validation, run 42508806292](https://github.com/AndreyCokol/My_shelter/actions/runs/42508806292): те же 1 742 domain/core/gameplay/world/layout assertions / 0 failures; Windows x64 export, offline headless smoke и **18 Kibyra textures** — PASS.
- [G0 docs, run 42508806370](https://github.com/AndreyCokol/My_shelter/actions/runs/42508806370): PASS. Linux лог: 31 Markdown-документ, 129 внутренних ссылок и 469 табличных строк — без ошибок.
- Состав checked suite assertions: `CORE 26; EVENT 45; GAMEPLAY 45; FOOD CATALOG 20; RESIDENT WORK FOOD 76; RUNTIME 87; COMBAT 23; UI CONTENT 24; ASSET 42; WORLD 155; LAYOUT 1199`.
- Из Linux CI загружены **23 реальных PNG** 1280×720 (сцены больницы/улицы/убежища/квартиры/лестницы + 13 окон, HUD и radial). Просмотрены как contact-sheet: палитры миров и окна действительно отрисованы, но визуальная проверка кадров не заменяет управление человеком. **PNG 1920×1080 отсутствуют в просмотренном артефакте PR #93**.

**Ограничение независимой проверки:** ZIP проверен структурно и прочитан README; `MyShelter.exe` на доступной Linux-среде **не запускался** (нет Windows/Wine и Godot runtime). CI логи — реальные внешние прогоны Godot, подтверждённые workflow statuses. Никаких придуманных локальных FPS/GUI тестов.

## 2. Матрица 25 механик на PR #93

Обозначения: `CI` = соответствующая подсистема присутствует и покрыта частью успешного автоматизированного прогона; `PARTIAL` = функциональность есть, но недостаточно для требуемой приёмки; `SOURCE_GAP` = в исходниках виден незавершённый аспект; `NOT_RUN` = требуемый ручной/стрессовый тест отсутствует. Это не 25 окончательных PASS.

| № | Механика | Что есть в PR #93 | Что остаётся |
|---:|---|---|---|
| 01 | Песочница, свободная игра | Сценарный цикл и независимые от Q03–Q07 хозяйственные действия; CI | Ручной свободный сеанс 15–35 минут NOT_RUN |
| 02 | Пролог, Система, Q01–Q02 | Одноразовые rewards; G до разблокировки Системы; исправление текста Q02 | Графический UX новичка NOT_RUN |
| 03 | WASD/стрелки, движение, 90° камера | `Player` + WorldHost, physics, top-down; CI | Проверка всей раскладки на Windows PC с активным UI NOT_RUN |
| 04 | Атака, уклонение, LOS, урон | `Player.try_attack`, `has_clear_line_to`, `dodge`, combat tests | Hit animation синхронизирована только примитивной отрисовкой; ручной бой NOT_RUN |
| 05 | Зомби, HP, AI, преследование | HP сохраняется по локации; LOS, patrol; CI | Позиция/alert/noise при повторной загрузке сцены **не сериализуются**; навигация вокруг стен ограничена |
| 06 | Оружие, XP, экипировка | `game.equip_weapon`, `combat.weapons`, XP bonus, tests | UX смены оружия, анимации, баланс P1 |
| 07 | Вход в убежище всегда | G/HUD работает до Q01, сохранение исходной локации и позиции; CI | Ручные клавиши/все сочетания модальных окон |
| 08 | Смерть и восстановление | `game.player_defeated` и безопасный restart; recovery tests | Безопасность фиксированной точки (120,260) на всех возможных картах |
| 09 | Процедурные улицы/дома/16 больничных этажей | Generator v5, **132 seed**, 1199 layout checks, paired exits, v4 compatibility | Визуальный аудит изменённых этажей/переходов + тест маршрутов после строительства |
| 10 | Сбор лута, кеши, возобновляемые ресурсы | Команды `game.resource_collect`, `game.salvage`, `game.hospital_cache`, unique receipts | Ручная проверка взаимодействий и подсказок |
| 11 | Графика двух миров и анимации | Две палитры + 18 texture assets в экспорте; PNG views | `Player._draw` и `Enemy._draw` всё ещё рисуют примитивы: **не интегрированы требуемые 64×64 spritesheets с 4 направлениями** |
| 12 | Ферма, вода, рост и порча | Clock deadlines, состояния, исторические crop config, CI | Длительный UX/баланс без QA ускорения |
| 13 | GameClock, пауза, отдых | Shared planner/ticks, pause, rest; CI | Долгосрочный drift/perf на реальном ПК |
| 14 | Инвентарь, склады, резервы, перенос | Атомарные команды, replay receipts, storage; CI | Проверка UX частичных стеков/недостатка места |
| 15 | Системный магазин, монеты, посылки | Rule-driven цены, атомарный расход, idempotency; CI | Окно и ошибки на ручном Windows UX |
| 16 | Добровольное заселение, питание | `edible` whitelist, reserve/consume, исторические receipts, negative tests | Длинные смешанные сохранения/реальная GUI |
| 17 | Работа жителей и расход еды | **Исправлено в PR #88→93:** любое разрешённое `edible`, детерминированный выбор, 76 tests | **В ранее переданном EXE не исправлено**; многодневный баланс P1 |
| 18 | Строительство, демонтаж, крафт | Реализованы команды, здания, тесты | Массовая застройка не должна перекрыть все обязательные пути; отдельная property-проверка |
| 19 | Диалоги NPC, отказ, согласие | Реализованы и тестируются отдельные состояния/действия | Ручной UX, сохранение после многократного отказа |
| 20 | Экспедиции, торговля, события | Есть gameplay commands и CI | Реальный темп, награды, пограничные условия взаимодействий |
| 21 | HUD, Left Ctrl radial, G, 13 панелей | Отрисовка 1280×720 PASS, предметы/радиальное меню настоящие | **1920×1080 визуальные регрессии** существуют в отдельном [PR #90](https://github.com/AndreyCokol/My_shelter/pull/90), **не включены в SHA #93** |
| 22 | Сохранение/загрузка, fault/recovery | В PR #93 staging, byte-compare, backup, rejected history, actor/world snapshot | Windows power-loss/kill-process tests NOT_RUN; **выданный EXE старее этих исправлений** |
| 23 | Новая игра, архивирование слотов | Реализован reset/archive, негативные тесты частично | Сбой `reload_current_scene`/повреждённый archive и повторный restart при наличии нескольких slots |
| 24 | Производительность, EventBus, receipts | Bounded EventBus, compact receipts, отдельные benchmarking PR | [PR #90](https://github.com/AndreyCokol/My_shelter/pull/90) и [PR #91](https://github.com/AndreyCokol/My_shelter/pull/91) содержат расширенные профили, **не включённые в #93**; 30 минут FPS/RAM NOT_MEASURED |
| 25 | Windows сборка, ассеты, релиз | Linux + native Windows CI + offline Windows export PASS; 18 Kibyra | Windows GUI-плейтест, независимое A0/A5 review, права на публичное распространение NOT_DONE |

**Приоритеты вне данного MVP:** полноценный Лувр, оборона группами, расширенная колония, 1000 жителей, финал книги; пространственный осколок помечен `LATER`. Нельзя объявлять отложенные функции багами P0.

## 3. Реестр новых или актуализированных проблем

| ID | Статус | Приоритет | Факт/гипотеза, воспроизведение | Что закрывает |
|---|---|---|---|---|
| **BLD-01** | **CONFIRMED BUILD MISMATCH** | **P0** | Выданный ZIP README указывает `1ea01bd`; PR #93 `db10a24` на 11 commits новее. Старый exe содержит `Work.FOOD = "crop.potato"`, новый использует `consume_shift_ration`, а также обновлён checkpoint flow. | На проверенном SHA #93 собрать временный Windows ZIP и убедиться, что VERSION/README/действия соответствуют binary SHA. Не объявлять сборку полной до GUI. |
| **AI-01** | **STATIC-CODE CONFIRMED**; runtime test NOT_RUN | **P1** | `game/scenes/worlds/world.gd::bind` при повторном входе создаёт `Enemy.new()` и ставит `foe.position=layout.enemy` (для patrol — `foe.patrol[patrol_index]`). В persisted state переносится только `enemy_health`; поля `alert_remaining, last_noise, hit_cooldown, current_position` из `enemy.gd` не восстанавливаются. При уходе через G и возврате можно сбросить погоню/позицию живого врага. Ранее [Issue #63](https://github.com/AndreyCokol/My_shelter/issues/63) формулировался как HP+aggression; HP решён, **aggression/position — не доказаны**. | Сначала утвердить правило: временный AI reset или persistence? Если должен сохраняться — сохранить location-bound position+AI state с учётом времени в убежище, тест G→возврат, save/load, стен/коллизий. |
| **AI-02** | **STATIC-CODE CONFIRMED DESIGN GAP** | P1 | В `Enemy._physics_process` враг идёт напрямую `direction_to(target)` через `move_and_slide()`; `NavigationAgent2D`/обход препятствий не реализованы. В помещениях враг может застревать за препятствием. | Navigation/pathfinder либо явно утверждённое простое chase AI; тест вокруг стены в 2–3 планах. |
| **ART-01** | **CONFIRMED MISSING SCOPE** | P1 | В `Player._draw` и `Enemy._draw` нарисованы круги и прямоугольники вместо согласованных pixel-art 64×64 четырехсторонних move/attack spritesheets. | Полный art import и визуальные/тайминговые тесты; до этого не ставить «анимации готовы». |
| **UX-01** | **ACCEPTANCE NOT_RUN** | **P0 для G4** | В PR #93 23 PNG только 1280×720; 1920×1080 PNG/13 bounds тесты добавлены в отдельный PR #90, не интегрированы на том же SHA. Реального Windows GUI-плейтеста нет. | Объединить нужные #90/#91 **осмысленно**, прогнать Linux+Windows CI на одном SHA; вручную проверить 1280×720/1920×1080, controls, 13 panels. |
| **SAVE-01** | **NEGATIVE TEST GAP** | P0 для релизной приёмки | CI симулирует ошибки записи, но отсутствует доказанная реальная Windows power-loss/kill-process при checkpoint overwrite и с последующим восстановлением. | Тест backup/rejected files и consistency всех systems, без потери последнего валидного save. |
| **WORLD-01** | **TEST GAP** | P1 | Связность процедурно созданного графа проверена, но не доказана после многочисленных player-build placement + reload; door/spawn/crops могут стать недоступны. | Property-based tests на placement seeds + BFS доступности критических точек после изменений. |
| **RESPAWN-01** | **RISK, НЕ БАГ** | P1 | В `game.player_defeated` и `GameApp.player_defeated` позиция respawn жёстко `(120,260)`, при этом world layouts различны. Вопрос, всегда ли это безопасная точка. | Test for each playable scene/seed, collision and reachable goal, fallback spawn. |
| **PERF-01** | **NOT_MEASURED** | P1 | Compact receipts сохраняют историю действий, 100k EventBus + save profile — отдельные PR #90/#91. Не доказаны FPS/heap/runtime limits. | 30-минутное испытание CPU/RAM/FPS + 10k–100k actions при целевой сцене. |
| **FLOW-01** | **TEST GAP** | P1 | `GameApp.new_game` архивирует checkpoint/`.bak` до `fresh` early return и `reload_current_scene`. Возможные сбои архивирования/возврата нужны в отдельном test matrix; дефект не воспроизводился. | Fixtures fresh save, slots with data, duplicate archive names, simulated rename/reload failure, guarantee no lost save. |
| **PROC-01** | **DOC/ACCEPTANCE GAP** | P1 | Текущие 4 района, 16 больничных этажей, 8 этажей жилья, 4 улицы / 30 nodes; пользовательские множители **улицы ×12, здания ×4** требуют численного baseline и визуального утверждения; не приравнивать лишь количество nodes к площади. | Baseline rectangle/coordinate + layout scaling, perf checks, сравнительные карты. |
| **LEGAL-01** | **RELEASE GATE** | P1 | Публичное распространение исходников/исполняемого файла требует отдельной проверки прав на книжную адаптацию и внешние материалы; закрытый личный прототип не даёт лицензий на перепубликацию. | Asset license manifest, decision public/private, owner approval. |

**Уже исправленные в нынешнем кандидате — НЕ дублировать как новые runtime bugs:** физическая уникальность больниц F24 (#76), edible whitelist F25 (#77), экипировка F07 (#62), текст Q02/магазин F10 (#65), работа жителей F09 (#64), HP врагов F08 (#63 — **только HP**, не position/alert).

## 4. Новые регрессионные тесты (требования к реализации)

| ID | Предусловия и шаги | Ожидаемое | Статус |
|---|---|---|---|
| **CT-80** | Скачать личный ZIP, извлечь README, сравнить source SHA и `git merge-base` latest candidate | Сборка помечена accurate SHA, нет неучтённых исправлений | **FAIL** как соответствие старого EXE нынешнему PR93 |
| **CT-81** | Настроить `food.accepted_food_type_ids` на съедобный предмет, кроме картофеля; назначить смену с резервом и после reload | Работа оплачивается допустимым нерезервированным видом, 1 списание | **PASS** в suite `RESIDENT WORK FOOD` PR93; **нет** в выданном EXE |
| **CT-82** | Нанести частичный урон живому патрульному, вызвать шум/агро, G → вернуться → save/load | HP и **утверждённое поведение** позиции/агрессии одинаковы | **NOT_RUN**, статический gap AI-01 |
| **CT-83** | Увести зомби вокруг стены с дверью на 3 планах; ждать заданный лимит | AI либо обходит, либо ограничение официально записано | NOT_RUN |
| **CT-84** | Создать 100 комбинаций построек на карте, затем seed+reload | Ключевые двери, поле, хранилище доступны из spawn; no softlock | NOT_RUN |
| **CT-85** | На **одном интеграционном SHA** 1280×720 и 1920×1080: 13 окон, radial, G, inventory, HUD | Нет clipping, перекрытия input, screenshot dimensions correct | CI PARTIAL PR93 / тесты 1080 в отдельном PR90 |
| **CT-86** | Windows GUI keyboard+mouse play 15–35 min и ручной save/load/contended UI | Все P0 циклы завершены, блокирующих багов нет | NOT_RUN |
| **CT-87** | Windows kill-process в 3 фазах write/replace/recovery, повторная загрузка | Неповреждённый предыдущий durable state или восстановленный committed one | NOT_RUN |
| **CT-88** | Проверить native 64×64 4-dir move/attack и ориентацию hit boxes во всех локациях | Корректные пиксельные спрайты вместо примитивов | NOT_IMPLEMENTED |
| **CT-89** | Отдых/ферма/NPC/shop/10000 transactions, 30m на Windows ПК | Данные целы, замерены FPS, latency, RAM, save cost | NOT_MEASURED |
| **CT-90** | Правильные ошибка/откат при `new_game` с поврежденным и валидным primary/backup | Нет потери save, понятный UI, новая кампания создаётся | NOT_RUN |
| **CT-91** | На новой сборке PR93 сверить ZIP SHA, версию кода, затем репродукции #64 и recovery | Исправления действительно в EXE, automated и GUI доказательство | NOT_RUN для новых байтов EXE |

## 5. Итоговый статус и порядок работы

**Нельзя утверждать «все механики проверены и багов нет».** Есть надёжное автоматическое ядро, 1 742 + 28 PASS на PR93; при этом:
1. **P0:** собрать новый ZIP из общего актуального SHA и не подменять им старую ревизию без уведомления; выполнить CT-80/91.
2. **P0 для приёмки:** объединить 1080p UI проверки с актуальным кодом + ручной Windows GUI/контроль 15–35 минут, CT-85/86.
3. **P0 для релизной надёжности:** Windows crash/save CT-87.
4. **P1:** решить спецификацию AI persistence (AI-01, CT-82), pathfinding (AI-02), post-build accessibility, spritesheet assets, perf.
5. **G0/G4:** независимое A1–A5/A0 review, owner SHA freeze, только после этого merge/release.

**Точное заключение:** `SHIPPED_ZIP=PR83_SHA / LATEST_INTEGRATION=PR93_SHA / CI_CORE_LINUX_WINDOWS=PASS / 1280_VISUAL=PASS / 1920_ON_LATEST=NOT_RUN / WINDOWS_GUI=NOT_RUN / ENEMY_AI_PERSISTENCE=SOURCE_GAP / ART_64_ANIM=NOT_IMPLEMENTED / G0_G4=NOT_ACCEPTED`.


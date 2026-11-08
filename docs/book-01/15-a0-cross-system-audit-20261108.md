# 15 — Повторный A0-аудит механик: актуальный код, отрицательные проверки и риски интеграции

**Дата:** 08.11.2026 · **Роль:** A0 — независимый вертикальный сверщик/советник A5. **Основной baseline:** [PR #72](https://github.com/AndreyCokol/My_shelter/pull/72), SHA `82b9ae89be761c448a1bb66d50d3e19f43553088` (включает PR #50/51/52/58/60/69 и объединение исправлений #66). **Параллельно:** [PR #71](https://github.com/AndreyCokol/My_shelter/pull/71) проверяет отдельные правила календаря и сохранений; [PR #73](https://github.com/AndreyCokol/My_shelter/pull/73) добавляет строгие физические fingerprints процедурного мира. PR #67 с исходной матрицей 25 механик — [документ 14](14-mechanics-code-audit-20261108.md). **Все PR остаются draft/open.** `main` и G0 не объявлены обновлёнными/утверждёнными.

**Факт тестирования:** [Linux PR72](https://github.com/AndreyCokol/My_shelter/actions/runs/42502907823) = **560 Godot assertions/0 failures + 28 software-rendered checks/0 failures**; [Windows PR72](https://github.com/AndreyCokol/My_shelter/actions/runs/42502907873) = Godot tests/export/headless PASS, 18 Kibyra textures; [Docs PR72](https://github.com/AndreyCokol/My_shelter/actions/runs/42502907816) PASS. **Это не означает прохождения новых проверок CT-71–79**. Данный аудит выполнен по исходникам + логам действительного CI, **без ручного Windows GUI**.

## 1. Перепроверка всех 25 подсистем

Обозначения: `PASS_AUTOMATED` — существует тест и зелёный CI конкретной ветки; `PARTIAL` — механика есть, но обязательные/негативные сценарии не закрыты; `FAIL_CONFIRMED` — фактически проваленный тест; `DESIGN` — незакреплённое игровое правило; `NOT_RUN` — необходимое испытание не проводилось.

| № | Механика | Что действительно проверено / что отсутствует | Вердикт |
|---|---|---|---|
| M01 | Песочница и необязательные задания | Q01–Q07, выбор отслеживания и продолжение действий после обучения в доменных tests; человека без подсказок не проверяли | PARTIAL: UX NOT_RUN |
| M02 | Обучение и открытие Системы | Начальная награда однократна; G работает до Q01; название Q02 «Открыть убежище» остаётся недостоверным (Issue #65) | PARTIAL / F10 OPEN |
| M03 | Вид 90° и движение | Top-down camera, Keyboard movement, процедурные стены; Windows GUI с разными масштабами не пройден | PASS_AUTOMATED / GUI NOT_RUN |
| M04 | Бой: атака, LOS, уклонение | Physics LOS героя и зомби + dodge + смерть в PR72; выбор оружия не влияет на фиксированный урон 25 | PARTIAL / F07 OPEN |
| M05 | Зомби: ранение, AI, преследование | PR72 сохраняет HP врага по локации и тестирует переходы/загрузку; путь AI вокруг стен NavigationAgent отсутствует | PASS_AUTOMATED / AI TEST_GAP |
| M06 | Оружие, опыт и уровень | Нож как награда, XP учитывается, но equip + характеристики + level-up не реализованы | MISSING_FUNCTIONALITY / #62 |
| M07 | Убежище по G всегда | PR #50→72: G/radial/HUD до первого врага, во время боя, из дома/улицы/этажа, save/load HP; GUI вручную не проверен | PASS_AUTOMATED / GUI NOT_RUN |
| M08 | Смерть и восстановление | PR #66→72: zero-HP reload/повтор ошибки сохранения и правильный блок перехода проверены; координата respawn 120×260 фиксирована | PASS_AUTOMATED / checkpoint DESIGN |
| M09 | Больницы, квартиры, улицы, двери | 128 seed graph/path tests PASS, но новый физический fingerprint PR73 **FAIL для 16 разных больничных этажей на всех 8 seed** (11–14 вместо 16) | **FAIL_CONFIRMED / #76** |
| M10 | Ресурсы, поиск припасов | Cooldown, однократные hospital caches и физическое взаимодействие тестируются, полный GUI path нет | PASS_AUTOMATED / GUI NOT_RUN |
| M11 | Зомби-мир vs убежище и 64×64 анимации | Разные палитры в WorldArt; персонажи в runtime рисуются примитивами, spritesheets 64×64 не встроены | PARTIAL / art scope |
| M12 | Ферма и урожай | Посадка/полив/рост/сбор/порча; PR #51 сохраняет историю сроков при изменении баланса | PASS_AUTOMATED / длительный баланс NOT_RUN |
| M13 | Единые часы и отдых | Calendar planner и pause; fractional fastpath протестирован в параллельных ветках #60/#71; окончательный общий SHA с #72 ещё не зафиксирован | PASS_SEPARATE_BRANCHES / FINAL_INTEGRATION_NOT_RUN |
| M14 | Инвентарь/склад/резервы | Перемещения, лимиты и закреплённые за NPC резервы, save replay; UI без частичного переноса | PASS_AUTOMATED / UX GAP |
| M15 | Магазин и деньги | Domain price из правил, фактическое списание защищено; видимая кнопка жёстко показывает «2 семени / 3 монеты» | PARTIAL / F10 OPEN |
| M16 | Заселение и питание NPC | PR #66→72 исправил исторические food receipts и повторную проверку резервов, включая compact/legacy формат; валидатор списка еды разрешает непищевые предметы | FIX_CANDIDATE_PASS / **F25 NEW** |
| M17 | Работа жителей/смены | Смены и дедлайны проходят tests; платой за смену остаётся только картофель `crop.potato`, хотя рацион допускает другое | PARTIAL P1 / #64 |
| M18 | Строительство и ремесло | Постройки/демонтаж, шкафы, хранилище, кровати; нет полного физического доказательства проходов после всех сочетаний | PASS_AUTOMATED / geometry TEST_GAP |
| M19 | NPC/контракты/добровольность | Отказ/принятие/food shortage + переповтор тестируются; полноценные диалоги и реальный UX ограничены | PARTIAL / UX NOT_RUN |
| M20 | Экспедиции, торговля, события | Этапы, однократная выдача наград и окна контрактов тестируются; разница времени торговли vs контрактов — design-open | PASS_AUTOMATED / DESIGN |
| M21 | HUD, Left Ctrl, G, окна | PR #50→72 объединяет radial и G, тесты modal pause/focus/28 render; нет ручного Windows UX | PASS_AUTOMATED / GUI NOT_RUN |
| M22 | Save/load и ошибки диска | PR72 поддерживает старые/новые receipts, исторические правила еды, врагов, crop deadlines, backup/fault; произвольный переход версии ruleset не мигрируется автоматически | PASS_AUTOMATED / RULESET_POLICY OPEN |
| M23 | Создание новой игры и архив | Код архивирования слотов и возврат при fail есть; полная fault matrix и восстановление после OS crash не проверены | TEST_GAP |
| M24 | Производительность и долговременная идемпотентность | EventBus bounded, compact receipts PR #69/72 уменьшают synthetic JSON на 51,36%; общая история команд **остаётся O(N)**; реальный FPS NOT_MEASURED | PARTIAL / #35 |
| M25 | Windows x64/офлайн/ассеты/права | Windows headless export PASS; Kibyra 18 PNG; внешние HappyHustle ZIP отсутствуют и лицензия архива не проверена; закрытый human build NOT_RUN | PARTIAL / #14/#45/#46 |

## 2. Проверенные исправления старых ошибок — не открывать дубликаты

| Исходный дефект | Исправление и доказательство | Итог |
|---|---|---|
| **F06 / #61 — старый NPC save отвергается новым балансом еды** | [PR #66](https://github.com/AndreyCokol/My_shelter/pull/66) заменяет валидацию текущих food rules исторической квитанцией; [PR #72](https://github.com/AndreyCokol/My_shelter/pull/72) совмещает это с `ActionReceipt.data()/fingerprint()` обоих форматов. [CI PR72](https://github.com/AndreyCokol/My_shelter/actions/runs/42502907823) PASS | `FIX_CANDIDATE_CI_PASS`; review + main merge pending |
| **F08 / #63 — раненый зомби восстанавливается при G** | [PR #66](https://github.com/AndreyCokol/My_shelter/pull/66) хранит `world_states.enemy_health[scene]`, PR72 повторно интегрирует с save/load, defeat recovery, LOS | `FIX_CANDIDATE_CI_PASS`; дизайн положения/агрессии врага после возврата требует отдельного решения |
| **F03/F04 — накладные расходы tick и EventBus** | [PR #57](https://github.com/AndreyCokol/My_shelter/pull/57) bounded EventBus, [PR #68](https://github.com/AndreyCokol/My_shelter/pull/68) fractional fastpath, [PR #71](https://github.com/AndreyCokol/My_shelter/pull/71) combined regressions, PR72 inherits another reviewed fastpath via #60. | Частичный PASS, **все параллельные изменения ещё не проверены в одном итоговом PR** |
| **F05 — размер durable receipts** | [PR #69](https://github.com/AndreyCokol/My_shelter/pull/69) и PR72: compact v1 + legacy replay + backup. На 10k операций 2,217,500 → 1,078,610 байт (−51,36%). | Размер **уменьшен, но по-прежнему O(N)**; без произвольного удаления квитанций |

## 3. НОВЫЕ подтверждения и проблемы

### F24 — **критерий 16 уникальных этажей больниц нарушен: подтверждённый CI FAIL**

[Issue #76](https://github.com/AndreyCokol/My_shelter/issues/76), [PR #73](https://github.com/AndreyCokol/My_shelter/pull/73), `game/tests/e2e/run_layout_fingerprint_tests.gd`: физические signatures нормализуют `walls,doors,rooms`; номера/labels/seed не считаются разнообразием. На [Linux](https://github.com/AndreyCokol/My_shelter/actions/runs/42503656609) и [Windows](https://github.com/AndreyCokol/My_shelter/actions/runs/42503656675) **8 из 8 seed провалили требование 16 различимых этажей**:

| Seed | Уникальных / требовалось | Статус |
|---|---|---|
| 0 | 11 / 16 | FAIL |
| 1 | 12 / 16 | FAIL |
| 54 | 12 / 16 | FAIL |
| 127 | 13 / 16 | FAIL |
| 128 | 12 / 16 | FAIL |
| 1023 | 14 / 16 | FAIL |
| 65535 | 12 / 16 | FAIL |
| 2147483647 | 12 / 16 | FAIL |

8 квартирных этажей, 4 улицы, graph connectivity и paired stair exits **PASS** в том же тесте. [`BuildingPlan.checked`](../../game/systems/world/building_plan.gd) может возвращать fallback `posmod(pattern,3)`; генератор выбирает ограниченный набор вариантов. Допустимых разных геометрий каталога — 20, но распределитель не гарантирует 16 уникальных в одном мире. Изменять `generator_version` только с сохранением существующих старых save/manifest; нельзя исправлять тест простой сменой pattern labels.

### F25 — **непищевой предмет разрешён как пища: дефект валидации конфигурации**

[Issue #77](https://github.com/AndreyCokol/My_shelter/issues/77), [`GameRules.validate`](../../game/data/game_rules.gd) разрешает любой `accepted_food_type_ids`, который существует в `rules.items`. Типы `tool.basic` (нож) и `material.salvage` (утиль) находятся в `items`. [`GameplayCommands.game.recruit`](../../game/systems/gameplay/gameplay_commands.gd) списывает/резервирует их как еду, если перечислить в `accepted_food_type_ids`. Для `units_per_resident=1,accepted_food_type_ids=["tool.basic"]` валидация правил по этому критерию **не отклоняет несъедобный item**. Это подтверждённый путь по коду; отдельный новый Godot тест **NOT_RUN**. Нужны food-category/edible metadata и отказ при неправильной конфигурации без потери старых food receipts.

### F26 — **нет единого доказательства совместимости параллельных интеграционных веток**

[PR #71](https://github.com/AndreyCokol/My_shelter/pull/71) вводит правила clock/ruleset safety и дополнительную проверку linked food receipts; [PR #72](https://github.com/AndreyCokol/My_shelter/pull/72) работает с `ActionReceipt` и историческим food rule; [PR #73](https://github.com/AndreyCokol/My_shelter/pull/73) выявляет физические дубликаты. **Сумма зелёных CI разных PR не равна зелёному CI итогового коммита**, особенно в общих `gameplay_state.gd`, `CoreSession`, calendar/receipt и layout. `INTEGRATION_NOT_RUN` до общего SHA. Нельзя повторно объединять старые PR #38/#39 или слепо заменять исправленный валидатор из #72 кодом #71/#69.

### По-прежнему открытые F07/F09/F10/F11/F14/F17/F21/F23

- **F07 / #62 P0:** нож не влияет на фиксированный урон 25, навыки/уровни в state не представлены. Требуются реальная экипировка и тест CT-57/58 либо явное изменение P0 решения.
- **F09 / #64 P1:** цена работы жителя жёстко `crop.potato`, не следует смешивать её с историческим food-receipt исправлением.
- **F10 / #65 P0:** Q02 «Открыть убежище» при доступном G с начала и жёсткие цены UI.
- **F11 P0:** fixed respawn position `(120,260)` требует проверки проходимости и соответствия «последней безопасной точке».
- **F14 art:** 64×64 top-down spritesheet move/attack пока не реализован для игрового героя/зомби; это art scope, не утверждать, будто анимации готовы.
- **F17/F21:** реальная проходимость после многократной стройки и навигация врагов вокруг сложных стен не доказаны.
- **F23:** публичный GitHub при личном приватном прототипе, HappyHustle ZIP/licensing отсутствуют, GUI Windows 15–35 минут не измерен.

## 4. Дополнение обязательных тестов (сразу после CT-53–70)

| ID | Критерий | Статус |
|---|---|---|
| **CT-71** | Для 8 edge seed и далее 128+ seed одновременно **16 различных геометрических fingerprints** больниц; корректная новая generator_version и legacy save | **FAIL по 8 seed в PR #73** |
| **CT-72** | Не разрешать `tool.basic`, `material.salvage` и `material.lamp_kit` как `food.accepted_food_type_ids`; допускается `crop.potato`, существующая legit food | NOT_RUN, static code path confirmed |
| **CT-73** | В одном итоговом SHA: food receipts старого и compact форматов + 2→3/consume + enemy HP/G + clock tick + ruleset mismatch + rollback | NOT_RUN (только отдельные ветки PASS) |
| **CT-74** | После изменения generator_version старый valid save возвращает прежнюю планировку/двери/лестницы; новые seed используют исправленный allocator | NOT_RUN |
| **CT-75** | NPC с историческим `food_receipt_id` при `ActionReceipt` v1: load/replay, старые поля, повреждённые квитанции, fault-injection и резерв | PASS_PARTIAL в PR72, owner cross-review NOT_DONE |
| **CT-76** | После 100 переходов G с ранеными врагами world states и HP остаются согласованны; никаких повторных уникальных наград | NOT_RUN на long-run |
| **CT-77** | На одном SHA и реальном Windows GUI: Left Ctrl, G, бой, постройки, инвентарь, farm, death, NPC, save/reopen; реальный 15–35-минутный UX | NOT_RUN |

## 5. Порядок разрешения и ownership

1. **A2 + A5:** [#76](https://github.com/AndreyCokol/My_shelter/issues/76), реальный геометрический FAIL. Сначала минимальное доказательство root-cause, потом поправка allocator/generator с защищённой версией; никаких фиктивных «разнообразных» названий.
2. **A1 + A3:** [#77](https://github.com/AndreyCokol/My_shelter/issues/77), edible validation; negative tests без потери historical NPC food receipts из PR72.
3. **A1/A2/A3/A4/A5:** объединить _только совместимые_ изменения PR71/72/73 на одном SHA, прогнать CT-73/74/75 и весь Linux+Windows+Docs+render suite. A0 — независимое review, не author approval.
4. **A2/A5:** F07 weapon/level и F10 Q02/shop pricing — обязательные для заявленного P0; F09 работа жителей P1.
5. **A5 + A0:** выполнить реальную Windows GUI/UX, лицензии ассетов, profiler и private artifact release; никакого объявления `G0_APPROVED`/merge без owner.

**Итог:** `25_MECHANICS_SECOND_PASS_DONE / PHYSICAL_HOSPITAL_UNIQUENESS_FAIL_CONFIRMED / NON_EDIBLE_FOOD_CONFIG_CODE_DEFECT / CROSS_BRANCH_REVIEW_REQUIRED / CT71–77_PARTIALLY_NOT_RUN / G0_BLOCKED / G4_NOT_ACCEPTED`. Правило владельца **«переход в убежище всегда доступен»** не пересматривать в виде cooldown или обязательного квеста.

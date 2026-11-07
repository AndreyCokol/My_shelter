# A0 — проверка реального кода и вертикальных рисков, 7 ноября 2026

**Audit mode:** A0 independent static code review & advice to A5 · **Target:** [PR #31](https://github.com/AndreyCokol/My_shelter/pull/31) and inherited PR stack #7 → #16 → #18 → #20 → #22 → #24 → #26 → #28 → #30 → #31 · **Target head SHA:** `c8c94b9cae41edadff28fe9ac965687acbe172f0` · **Verdict:** `CHANGES_RECOMMENDED / GAMEPLAY_ACCEPTANCE_PENDING`.

**Method:** inspected actual GDScript, tests, architecture and GitHub Actions logs as an independent reviewing session; did **not** execute Godot locally, did not modify A1–A5 files, did not approve the PR or certify UX. Findings below distinguish code-proven behavior, predicted consequences and unexecuted regression scenarios.

## 1. Проверенные факты поставки

| Evidence | Факт | Вывод |
|---|---|---|
| [Linux CI 42373276704](https://github.com/AndreyCokol/My_shelter/actions/runs/42373276704) | **410 checks, 0 failures**: core 21, campaign 31, router 28, event 39, calendar 35, gameplay 41, edge 32, runtime 38, assets 40, world 105; rendered UI 19 checks PASS | Автоматические suite и software-OpenGL rendering подтверждены в CI, не равны ручной оценке игры |
| [Windows CI 42373276640](https://github.com/AndreyCokol/My_shelter/actions/runs/42373276640) | Та же Godot test suite PASS, Windows x64 release экспортируется и запускается в headless, 18 Kibyra textures присутствуют в PCK | Native Windows CI подтверждён, **не** личный запуск с GUI на целевом ПК |
| [PR #31](https://github.com/AndreyCokol/My_shelter/pull/31) | 26 сцен/узлов процедурного графа (4 района, 4 дома, 16 больничных этажей, стоянка и убежище), schema v4, 128 seed, 24 scene switch fixtures | Существенное увеличение scope и тестовой базы, но всё в открытом PR-стеке, `main` не содержит эти модули |
| [Issue #4](https://github.com/AndreyCokol/My_shelter/issues/4) / [PR #7](https://github.com/AndreyCokol/My_shelter/pull/7) | G0 `BLOCKED`, PR7 `DRAFT`, нет официальных review A1–A5/A0 | Вертикальная приёмка и нормативная база ещё не зафиксированы |
| [PR #18](https://github.com/AndreyCokol/My_shelter/pull/18) | В PR заявлено **отдельное разрешение владельца от 6 ноября на ограниченную реализацию G1a**, несмотря на непрошедший G0 | Нельзя считать отсутствие `G0_APPROVED` доказательством несанкционированного авторства кода; требуется явная запись исключения в Issue #4 |

## 2. Замечания с доказательствами

### A0-F01 · MAJOR · Рабочее сохранение может перестать загружаться при балансировке культуры

**Source:** [`game/state/gameplay_state.gd` lines 43–55](https://github.com/AndreyCokol/My_shelter/blob/c8c94b9cae41edadff28fe9ac965687acbe172f0/game/state/gameplay_state.gd#L43-L55), [`game/data/game_rules.gd` lines 4–15](https://github.com/AndreyCokol/My_shelter/blob/c8c94b9cae41edadff28fe9ac965687acbe172f0/game/data/game_rules.gd#L4-L15), [`game/state/campaign_model.gd` lines 29–40](https://github.com/AndreyCokol/My_shelter/blob/c8c94b9cae41edadff28fe9ac965687acbe172f0/game/state/campaign_model.gd#L29-L40).

**Direct observation:** для растущего/созревшего/испорченного поля валидатор требует `ripe_at == planted_at + rules.crop.grow_minutes` и `spoil_at == ripe_at + rules.crop.spoil_minutes`. В сохранении не фиксируется длительность конкретной посадки или immutable ruleset snapshot; `Rules.build()` использует `version="prototype-v1"`. Если при балансировке изменить `grow_minutes` (например с 180 на 240), старый checkpoint с растущей картошкой будет отклонён валидатором. Это **прогнозируемый отказ по коду**, а не проведённый нами тест на изменённом релизе.

**Acceptance to resolve:** тест `save with grow_minutes=180 → change balance to 240 → load old save` должен сохранить старый урожай с прежними deadline или провести явную безопасную миграцию. Варианты: сохранять `planted_growth_minutes/planted_spoil_minutes` для каждой посадки, либо сохранять и загружать таблицу версий конфигурации и мигрировать. Нельзя перезаписывать старые файлы при ошибке загрузки. **Owner:** A1 + A3, review A5/A0.

### A0-F02 · MAJOR / combat correctness · Удар в ближнем бою игнорирует стены

**Source:** [`game/entities/player/player.gd` lines 49–63](https://github.com/AndreyCokol/My_shelter/blob/c8c94b9cae41edadff28fe9ac965687acbe172f0/game/entities/player/player.gd#L49-L63), [`game/systems/world/world_layout.gd` lines 25–36](https://github.com/AndreyCokol/My_shelter/blob/c8c94b9cae41edadff28fe9ac965687acbe172f0/game/systems/world/world_layout.gd#L25-L36).

**Direct observation:** `try_attack` наносит `enemy.take_damage(25)` по дистанции менее 64 и скалярному произведению направления `>0.2`, **без запроса `direct_space_state.intersect_ray`/маски препятствий**. В каталоге карт есть стены толщиной 13–20 пикселей, и обе сущности могут оказаться в радиусе удара по разные стороны преграды. Следовательно, удары через тонкие стены не исключены логикой попадания.

**Acceptance to resolve:** авторизованный A2 тест Godot с непроходимым StaticBody2D между героем и противником (в пределах 64, направление на цель): `try_attack` анимацию играет, **урон 0**. Повторить без препятствия — урон 25. Проверить слои collision mask и фактическую визуальную сцену, исключив самих героя/врага из ray query. **Owner:** A2, UI impact review A5, independent A0 re-check.

### A0-F03 · MAJOR / scalability-risk · Полная копия и валидация кампании выполняются на каждом кадре

**Source:** [`game/systems/core/campaign_session.gd` lines 38–52](https://github.com/AndreyCokol/My_shelter/blob/c8c94b9cae41edadff28fe9ac965687acbe172f0/game/systems/core/campaign_session.gd#L38-L52), [`game/systems/core/core_session.gd` lines 193–210](https://github.com/AndreyCokol/My_shelter/blob/c8c94b9cae41edadff28fe9ac965687acbe172f0/game/systems/core/core_session.gd#L193-L210).

**Direct observation:** `Main._process(delta)` вызывает `Campaign.tick(delta)` каждый кадр. Тот всегда вызывает `CoreSession.apply_runtime`: `_state.duplicate(true)`, `JsonNumbers.normalize_numbers`, `_state_validator.call` с проверкой всей campaign, изменение `state_revision`, **даже если ни одна целая игровая минута не прошла**. При накоплении предметов, действий и процедурных состояний стоимость кадра растёт с размером сохранения. **Падение FPS не измерялось; это проверяемый performance-risk, не доказанный баг 60 FPS.**

**Acceptance to resolve:** измерить profiler/synthetic budget на 60 FPS с накопленными 100/1000/10000 receipts и 26 локациями, сравнить долю времени до/после; отделить накопление дробного остатка времени от полного deep-copy/validate на каждый render frame, сохранив корректное tick/rest и save/load. Определить, при каких state changes обязан расти `state_revision`. **Owner:** A1; нагрузочные сценарии A5/A0.

### A0-F04 · MAJOR / long-run-risk · История событий в памяти растёт без ограничения

**Source:** [`game/systems/core/event_bus.gd` lines 3–6, 40–65](https://github.com/AndreyCokol/My_shelter/blob/c8c94b9cae41edadff28fe9ac965687acbe172f0/game/systems/core/event_bus.gd#L40-L65), [`game/systems/core/core_session.gd` lines 245–252](https://github.com/AndreyCokol/My_shelter/blob/c8c94b9cae41edadff28fe9ac965687acbe172f0/game/systems/core/core_session.gd#L245-L252).

**Direct observation:** каждый уникальный `event_id` попадает в `EventBus._seen`, который очищается **только** после загрузки сохранения, без лимита, эвикции или TTL. При игровом времени 1 минута за реальную секунду `time_advanced` создаёт множество уникальных уведомлений при длительной непрерывной сессии. `_seen` не является persistence ledger, так что полный жизненный горизонт для истории уведомлений должен быть ограничен и задокументирован.

**Acceptance to resolve:** stress 100k разных `event_id` / длительная сессия, измерить память; принять bounded cache/dedup window без потери однократности **доменных транзакций** (её обеспечивают persisted receipts). Не изменять публичную семантику подписок и `state_loaded`. **Owner:** A1; review A0.

### A0-F05 · P1 / save growth-risk · Журнал успешных действий сохраняется без политики уплотнения

**Source:** [`game/systems/core/core_session.gd` lines 153–169](https://github.com/AndreyCokol/My_shelter/blob/c8c94b9cae41edadff28fe9ac965687acbe172f0/game/systems/core/core_session.gd#L153-L169), [`game/systems/core/checkpoint_store.gd` lines 19–44](https://github.com/AndreyCokol/My_shelter/blob/c8c94b9cae41edadff28fe9ac965687acbe172f0/game/systems/core/checkpoint_store.gd#L19-L44).

Любая успешная команда записывает `completed_actions[action_id]` с fingerprint и полным result; checkpoint каждый раз сериализует всю игру. Для бесконечной песочницы объём сейва и длительность записи будут расти. Не удалять записи уникальных наград/покупок без миграции и доказательства идемпотентности; отделить вечные доменные ID от краткосрочных повторов команд, определить retention/compaction policy, stress 10k операций. **Приоритет после P0, до длительного открытого плейтеста.**

## 3. Соответствие утверждённым решениям владельца — проверено на коде

- **Реализация присутствует**: attack/dodge A2; система и убежище; ферма + естественное время + rest; `food.units_per_resident` из runtime config, `reserve_mode`; optional Q03–Q07; сохранение schema4/процедурный мир. Режим gameplay `15–35 минут` **не измерен**.
- **Дополнительные функции** (camp economy, 16 больничных этажей, resident shifts, workshop) внесены до G0 freeze; необходимо явное обозначение как экспериментального объёма, чтобы не объявлять их обязательным P0. Независимая ручная оценка масштаба ещё не завершена.
- **UI A5 ownership**: `game/ui/game_ui.gd` изменяется в PR стеке #28–#31, но PR не имеет независимого code review; один GitHub author не позволяет достоверно установить персональный агентский ID исполнителя. [A0 Issue #13](https://github.com/AndreyCokol/My_shelter/issues/13) требует адресовать замечания A5.
- **Закрытый прототип**: GitHub repository сейчас публичен, release/бинарный public artifact не доказан; [Issue #14](https://github.com/AndreyCokol/My_shelter/issues/14) остаётся открытым. Статус game source in public не отменяется словами «закрытый прототип».

## 4. Непроверенные части

- **NOT_RUN BY THIS REVIEWER:** локальный Godot, hardware GPU UI, player-operated Windows desktop, человекочитаемый usability, 15–35 минут, истинный долгосрочный баланс и 100k событий стресс.
- **CI EVIDENCE VERIFIED:** Linux core and visual checks, native Windows headless export/start; по логу перечисленных suites = **410 checks PASS**, дополнительно **19 checks visual PASS** на software renderer. Скрипты могли не покрывать сценарии A0-F01..F05.
- **A0 status:** `STATIC_REVIEW_COMPLETE_WITH_FINDINGS / RUNTIME_INDEPENDENT_REVIEW_PENDING`. Это заключение отдельной обзорной сессии, **не** утверждение, что запущены шесть автономных агентов, и не сертификат G4.

## 5. Рекомендованный порядок

1. A2/A5: закрыть A0-F02 стеновое попадание (прямой пользовательский дефект).
2. A1/A3: решить A0-F01 миграцию crop rules/save до балансировки.
3. A1/A5: профилировать A0-F03, ограничить A0-F04 по тестам.
4. Зафиксировать результат G0: принятые владельцем продуктовые решения сохраняются, но новый код из PR #18–#31 идёт **по заявленному отдельному разрешению**, не является автоматическим `G0 APPROVED`.
5. A0 ревьюит фиксы; A5 принимает UI/G4 только после ручного Windows GUI/UX; не мержить стэк по одному зелёному CI.

**Процедура:** выводы не превращаются в вето A0; предметные авторы A1/A2/A3 и главный A5 принимают технические решения и документируют исправления/отклонение с аргументами. Владелец оставляет за собой публичное распространение и окончательную G0/G4 приёмку.

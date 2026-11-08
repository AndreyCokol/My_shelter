# 13 — Техническая верификация игрового прототипа и контроль G0

**Дата:** 08.11.2026 · **Статус:** `AUDITED / CONTRACT_v1.6_PROPOSED / G0_BLOCKED`. Это итог последовательной работы в одной сессии, а **не** персональное ревью A1–A5 и A0 и не утверждение владельца.

## 1. Единственная последовательная цепочка реализации

**Базовая реализация:** [PR #31](https://github.com/AndreyCokol/My_shelter/pull/31) (кандидат Godot 4.7.2, gameplay schema v4, процедурные сцены, сценарии игрока, UI и сохранения). Два параллельных ответвления были: [PR #38](https://github.com/AndreyCokol/My_shelter/pull/38) — Left Ctrl radial, [PR #39](https://github.com/AndreyCokol/My_shelter/pull/39) — shelter G. Они пересекаются в game_app/UI; их независимая приёмка не доказывает совместимость.

| Порядок | PR и commit SHA | Изменено | Фактическое подтверждение |
|---|---|---|---|
| 1 | [#50](https://github.com/AndreyCokol/My_shelter/pull/50), `44c337baa74ae4babb456babfd8e5f990d6473db` | Соединены Left Ctrl/radial, G/HUD+modal shelter always, точный return/HP, scene/recovery invariants, совместные тесты | [Linux CI PASS](https://github.com/AndreyCokol/My_shelter/actions/runs/42493610409), [Windows CI PASS](https://github.com/AndreyCokol/My_shelter/actions/runs/42493610339), visual 28/28 |
| 2 | [#51](https://github.com/AndreyCokol/My_shelter/pull/51), `b60b9972a870243c29aaf2f9daf5038e86fa5227` | Existing crops: сохранённые deadlines важнее новых grow/spoil конфигов; stamping новых культур; legacy save не переписывается | [Linux PASS](https://github.com/AndreyCokol/My_shelter/actions/runs/42494057177), [Windows PASS](https://github.com/AndreyCokol/My_shelter/actions/runs/42494057128), 7 дополнительных проверок |
| 3 | [#52](https://github.com/AndreyCokol/My_shelter/pull/52), `6399081e060f9282501c2ffaaf5f7f55d41ec6f4` | Raycast Line of Sight не позволяет melee damage через StaticBody2D wall | [Linux PASS](https://github.com/AndreyCokol/My_shelter/actions/runs/42494298184), [Windows PASS](https://github.com/AndreyCokol/My_shelter/actions/runs/42494298127), реальная физическая стена |
| 4 | [#53](https://github.com/AndreyCokol/My_shelter/pull/53), `3e0f567d5d79d3b0a0bb2e415b4f6232d4c1d6cb` | Sub-minute tick fast path, bounded EventBus history 4 096 IDs, новые stress fixtures | [Linux PASS](https://github.com/AndreyCokol/My_shelter/actions/runs/42494825276), [Windows PASS](https://github.com/AndreyCokol/My_shelter/actions/runs/42494825316) |

**Важно:** Это наследуемый стек; PR #51 основан на #50, #52 на #51, #53 на #52. **Не** мержить их в `main` по отдельности в произвольном порядке. После ревью предпочтителен один проверенный интеграционный head + документированный merge strategy и история SHA.

## 2. Прямые выводы по исходному коду

- **Владение состоянием:** `game/app/game_app.gd` формирует player-command envelope и отправляет в `game/systems/core/core_session.gd`. Domain mutations выполняются на tentative snapshot; durable receipt+snapshot commit до EventBus notification; после ошибки используется recovery. UI не должен писать квесты/XP/кошелёк напрямую.
- **Безусловное убежище:** `game/systems/inventory/campaign_commands.gd` допускает только shelter/return transition до `first_enemy_defeated`, не снимая gates с shop/parcel; `game/systems/scene_router/scene_router.gd` сохраняет обратный scene/точку/HP. `game/ui/game_ui.gd` сохраняет radial и modal pause ownership.
- **Сохранение культуры:** `game/state/gameplay_state.gd` проверяет фактические сроки уже посаженных культур и корректные timestamps/duration stamps; `game/systems/gameplay/gameplay_commands.gd` задаёт новым посадкам актуальную версию баланса. Полный ruleset_version migration **не реализован**.
- **Стены:** `game/entities/player/player.gd` использует physics ray query между игроком/врагом; атаки за препятствием блокируются. Остальные разновидности дальнего оружия/объектов не охвачены этим единичным melee тестом.
- **Время:** `game/systems/core/campaign_session.gd` пропускает подминутные кадры через ограниченный fastpath, а переход целой календарной границы проводит через полный planner. `clock_remainder` сохраняется при следующем durable checkpoint.
- **События и повтор:** `game/systems/core/event_bus.gd` допускает только ограниченный кэш transient deliveries (4 096), не источник exactly-once. `completed_actions` и доменные ID постоянны, но их рост пока не ограничен.
- **Канонический контракт:** только [05-integration-contracts.md](05-integration-contracts.md), новая редакция **v1.6-PROPOSED**, не старая v1.0 из PR #7 и не самостоятельный #07 из закрытого PR #5. Runtime gameplay save — **schema_version=4**, JSON v1 в §8 оставлен лишь как история.

## 3. Измерения нагрузки на журнал (A0-F05)

Добавлен тест `game/tests/core/run_performance_tests.gd` и включён в `tools/run_godot_checks.py`; для 100 / 1 000 / 10 000 **синтетических** receipt проверяет valid campaign state и измеряет `json_bytes/json_ms/duplicate_ms/validate_ms`.

**Статус числовых результатов на момент создания этого документа:** `PENDING_CI`. Точные результаты должны быть считаны из Linux/Windows CI **этого документационного PR** и зафиксированы в комментарии/последующей ревизии, с SHA, ОС, точной командой и лимитами. Замеры не представляют реальную 3/7/14-дневную игру.

**Решение по A0-F05:** пока не удалять persisted `completed_actions`: `action_id` в действующем коде произвольный и не ограничен надёжно последовательным watermark, поэтому удаление старого receipt может повторить уникальную награду. Безопасное сжатие потребует отдельного контрактного изменения, replayer compatibility, версии схемы и миграции старых checkpoint. Синтетический benchmark не является разрешением удалять данные.

## 4. Матрица независимой приемки

| Проверяющий | Что должно быть предметно подтверждено | Текущий факт |
|---|---|---|
| A1 — Core | save barrier/fault recovery, API v1.6, ruleset migration, event history/ledger | `FORMAL_REVIEW_PENDING` |
| A2 — Combat | LOS на разных планировках, G escape без reward, real-time input/physics | `FORMAL_REVIEW_PENDING` |
| A3 — Farm | old deadline compatibility, harvest, food/reservations, long rests | `FORMAL_REVIEW_PENDING` |
| A4 — Quest/NPC | Q01–Q02 onboarding, Q03–Q07 optional, consent/unique residents, no shard | `FORMAL_REVIEW_PENDING` |
| A5 — Chief/UI | HUD, Left Ctrl vs right Ctrl, G/ESC/modal/focus, usable 640x360, Windows GUI UX | `FORMAL_REVIEW_PENDING` |
| A0 — Independent | повторная проверка F01–F05, source/CI evidence, A5 code review | `FORMAL_REVIEW_PENDING` |
| Владелец | после реального review утверждает **конкретный final SHA** | `OWNER_SHA_PENDING` |

Технический аудит одной сессией **не** является шестью отдельными подписями. Надёжность релиза требует GUI на реальном Windows, 15–35 минут наблюдаемого UX, права на ассеты и решение об использовании публичного GitHub при закрытом личном прототипе (Issue #14).

## 5. Формальные выводы по G0

**Можно утверждать по CI:** последовательный P0-кандидат существует в PR #50→#53, модули прошли Linux/native Windows headless и software OpenGL visual, исправления по A0-F01/F02/F03/F04 имеют воспроизводимые тесты. Нет оснований считать документационную `main` такой сборкой.

**Нельзя утверждать:** G0/G4 готовы, миграция любого нового ruleset_version полностью поддержана, произвольные receipts безопасно удаляются, GUI Windows пройден на ПК пользователя, все A1–A5/A0 подписали ревью, HappyHustle скачан с допустимой лицензией.

**G0 остаётся BLOCKED:** [Issue #4](https://github.com/AndreyCokol/My_shelter/issues/4). Не выставлять APPROVED без формальных отзывов, ссылки владельца на точный SHA, решения по границам долговременного ledger и совместимости старых файлов.

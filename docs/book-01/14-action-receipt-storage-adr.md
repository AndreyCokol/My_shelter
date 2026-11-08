# ADR-14 — Компактные квитанции завершённых команд (A0-F05)

**Статус:** `IMPLEMENTED_IN_DRAFT_PR / OWNER_AND_INDEPENDENT_REVIEW_PENDING` · **Дата:** 2026-11-08 · **PR:** [#69](https://github.com/AndreyCokol/My_shelter/pull/69) · **Предшествующий P0:** [#60](https://github.com/AndreyCokol/My_shelter/pull/60) · **Блокер:** [Issue #35](https://github.com/AndreyCokol/My_shelter/issues/35).

## Проблема
До изменения каждый элемент `completed_actions[action_id]` хранил `fingerprint` и целый `CommandResult`, повторно записывая сам `action_id`, `ok`, `code`, `state_revision` и имена JSON-полей. Это безопасно для идемпотентности, но увеличивает размер/стоимость JSON по мере роста песочницы. Произвольные `action_id` и безусловное удаление старых квитанций несовместимы с точным replay. Записи `claimed_reward_ids` и доменные уникальные ID нельзя терять.

## Решение и ограничение

**Не удалять ни одну завершённую команду.** Для новых успехов хранить компактную версионированную запись:

```json
{
  "completed_actions": {
    "unique-action-id": [1, "semantic-sha256", 42, {"domain_receipt": "unchanged"}, "core.ok"]
  }
}
```

Индексы: `0 = receipt_format_version` (сейчас 1), `1 = semantic fingerprint`, `2 = original state_revision`, `3 = exact response data`, `4 = original message_key`. Внешние `schema_version=4` и `ruleset_version` не меняются; это допустимый вариант значения `completed_actions`, валидируемый вместе с кампанией. `action_id` по-прежнему присутствует в единственном ключе словаря. `ok=true`, `code=OK` для успешно завершённых действий восстанавливаются из версии формата; при повторе возвращается `code=ALREADY_APPLIED`.

**Replay:** `CoreSession.execute()` сравнивает semantic fingerprint до любых изменений; совпавший `action_id` возвращает исходные `state_revision`, `data`, `message_key` с кодом `ALREADY_APPLIED`, без транзакции и без новых событий. Иной payload при том же ID → `ACTION_CONFLICT`. Domain validator A4 читает `Receipts.data()`, поэтому `resident.food_receipt_id` не зависит от кодировки квитанции. UI не должен обращаться к внутренней записи напрямую.

**Старые сейвы:** историческое значение `{"fingerprint": "...", "result": {...}}` продолжает валидироваться и воспроизводиться. После загрузки **первое следующее успешно записанное действие** преобразует только канонические legacy-успехи в компактный формат в `tentative` состоянии, до общего checkpoint. Необычные старые записи с дополнительными полями остаются в исходном формате; их данные не теряются. При ошибке записи или откате conversion не попадает ни в RAM, ни в primary. Предыдущая валидная версия остаётся в `.bak`. `CheckpointStore` продолжает писать полный JSON со всеми доменами и квитанциями.

**Никаких новых прав игроку:** игра не разрешает claim/recruit/reward по отсутствующему persisted receipt; `claimed_reward_ids`, resident food allocations, инвентарь, XP, deadline и сцены сохраняют текущую логику. Это оптимизация хранения, не игровой баланс. Исторические схемы из другой версии `ruleset_version` по-прежнему **отклоняются**, а не мигрируют автоматически.

## Подтверждение испытаниями на PR #69

На проверенном commit `a22915841b03a5443fbfdef999b5792a6c1522a0`:

- [Linux Godot](https://github.com/AndreyCokol/My_shelter/actions/runs/42502159894) — все core/gameplay/world тесты PASS; `RECEIPT TESTS: 20 checks, 0 failures` и `PERFORMANCE TESTS: 4 checks, 0 failures`; 28 фактических visual checks PASS.
- [Windows x64 CI](https://github.com/AndreyCokol/My_shelter/actions/runs/42502159886) — native tests PASS, Windows release экспортирован, headless launch и 18 Kibyra textures PASS.
- [Documentation](https://github.com/AndreyCokol/My_shelter/actions/runs/42502159882) — consistency/live contract checks PASS.
- **Равные 10 000 операций:** прежний JSON 2 217 500 B → новый 1 078 610 B (**51,36% сокращения**); Linux сериализация нового блока 14,988 мс; Windows 28,227 мс. Это синтетический benchmark на GitHub runner, а не FPS в реальной игре.
- Проверены: старый JSON → корректная загрузка → replay → успешный commit → lossless compact → restart; откат `before_replace`, backup восстановление, недопустимая ревизия → отказ без изменения сессии, linked NPC food receipt (общие gameplay тесты).

## Неразрешённое

1. **Долговременный рост остаётся O(N).** Меньшее число байт на запись ≠ ограничение памяти/файла; 100 000+ действий по-прежнему потребуют benchmark и стратегии.
2. Для настоящего bounded journal нужно изменение контракта: например, stable semantic intent keys и периодическая агрегированная история с доказуемыми replay horizons, либо атомарный внешний ledger с recovery protocol. Нельзя безопасно удалить arbitrary `action_id` и одновременно обещать exact replay forever.
3. Границы store durability на Windows, большие save-файлы и правила миграции следующих `receipt_format_version` — предмет будущих ADR и fault-injection tests. Локальный JSON/backup не является криптографической защитой от ручного редактирования.
4. Независимое A1/A3/A4/A0 ревью, практический GUI/FPS и owner-approved G0 SHA **не выполнены**. Не объединять Draft PR в `main` и не закрывать Issue #35 целиком на основании одних CI.

## Следующая приёмка

Дождаться отдельного анализа A1 (идемпотентность, disk commit, malformed receipts), A4 (связанные NPC/еда), A0 (предыдущие замечания), затем проверять G0 по **точному финальному SHA** и решению владельца в [Issue #4](https://github.com/AndreyCokol/My_shelter/issues/4). Сверить единый нормативный кандидат [05](05-integration-contracts.md) перед freeze: этот ADR является уточнением реализации, **не вторым нормативным контрактом**.

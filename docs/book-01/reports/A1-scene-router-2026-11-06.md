# A1-04: SceneRouter, позиции и staged runtime load

Дата: 2026-11-06. Исполнитель: одна сессия Codex, A1. Issue #21. База: PR #20 / 9ebfcb151f94ea08bc1acaf817750797b9808591. Независимое ревью: REVIEW_NOT_PERFORMED.

## Результат

Реализован SceneRouter для смены Node2D world в WorldHost. Ресурсы поступают только из доверенного registry, а герой — единственный supplied Node2D A2 вне сменяемого world. Маркер EntryPoints/entry_id проверяется до записи; произвольные NodePath из save не принимаются. Старый world удаляется после подготовки нового и успешного checkpoint. UILayer не заменяется.

Campaign-core схема 2 сохраняет player.position, позиции посещённых сцен и last_outside_position. Возвращение восстанавливает прежнюю точку; первая смена использует Marker2D. Router.save захватывает текущую runtime-позицию. Схема 1 campaign-core отклоняется без неявной миграции/перезаписи; новый slot по умолчанию campaign-v2.json.

CoreSession получил runtime prepare/install/discard hooks: и команда, и load сначала проверяют кандидат и готовят runtime, затем публикуют согласованное состояние/сцену. committed/state_loaded следуют после монтажа. Ошибка подготовки/записи не заменяет живую сессию. Сбой после commit требует recovery, а не ложного rollback. Replay не перемонтирует прошлую сцену. Reentrant transition во время commit отклоняется. Назначенный, но исчезнувший runtime adapter не превращается молча в DTO-only.

Main.start_campaign(rules,worlds,actor,save_path) удерживает кампанию и router, включает Clock в _process и отклоняет повторный запуск. Без supplied модулей Main остаётся bootstrap. Реальный герой, игровые карты и UI не подменены тестовыми сущностями.

Числовая нормализация JSON вынесена в общий модуль и применяется также к живому состоянию: целые координаты не меняют тип после reload, дробные сохраняются. Добавлены общие fixtures для тестов кампании и router.

## Проверка

Godot 4.7.2.stable.official.ed1daf0bf, Linux. **21 core + 31 campaign + 26 router = 78 проверок, 0 failures**. Проверены реальные PackedScene/Node2D, а не только metadata. Import, Main smoke, отсутствие SCRIPT ERROR/ERROR/утечек и docs/diff integrity — PASS. Лог: [A1-scene-router-checks-4.7.2.log](A1-scene-router-checks-4.7.2.log).

```sh
GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 python3 tools/run_godot_checks.py
python3 tools/check_g0_docs.py
git diff --check
```

Сценарии: round trip двух миров/одного героя; дробная координата save/load; отсутствующий ресурс/маркер; path traversal entry; отказ до checkpoint; сбой после checkpoint и recovery; replay без телепорта; pause; согласованные события; reentrant команды; неподготовляемая сцена при load; отказ старой схемы; Main composition integration.

## Что открыто

- Настоящие карты и actor/controllers A2/A3/A4; сейчас сцены создаёт только тестовая fixture.
- Поведение игровых scene scripts, их коллизии/камера/ввод и scene lifecycle под независимым review.
- Runtime hooks — доверенные синхронные адаптеры. Сцены обязаны не менять домен в _init/_ready. При отказе после durable commit используется recovery; произвольные сторонние script errors не имеют гарантии автоматического rollback.
- Farm/Combat/Resident/Quest data и time planners; UI A5; полноценные E2E/UX; Windows export/rename/power-loss — NOT_RUN/NOT_IMPLEMENTED.
- G0 и G2–G4 не объявлены принятыми по результатам этих технических тестов.

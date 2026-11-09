# VISUAL/WORLD/UX — фактический статус на 2026-11-09

**Владелец потока:** A5 VISUAL/WORLD/UX, A2 world geometry only where owned; A0 — отдельная независимая приёмка.

**Единая база:** `a1ae8c0b68017ea4f4067a677a2d94029e1cac1d` (draft PR #130). `main`, CORE и delivery не изменялись.

## VIS-01 / HUD и журнал операций

Отдельная визуальная ветка `work/visual-world-20261109`; [PR #135](https://github.com/AndreyCokol/My_shelter/pull/135), исходник [PR #127](https://github.com/AndreyCokol/My_shelter/pull/127).

- Только `game/ui/game_ui.gd` и `game/tests/e2e/run_ui_content_tests.gd`: `app.snapshot(false)` для HUD и окна, реальные E2E-проверки журнала.
- **Доказанный результат:** Linux workflow `42608969989` и Windows `42608970131` выполняют 27/28 UI assertions; одна падает на `preview_rest`, т.к. CORE `game/app/game_app.gd` всё ещё вызывает `snapshot()`.
- **Статус:** `IN_PR / CI_FAIL_DEPENDENCY`, независимого релизного PASS нет. [CORE-API #136](https://github.com/AndreyCokol/My_shelter/issues/136) передан владельцу CORE.
- Отдельное измерение 20 HUD refresh с 10 000 receipts опубликовано только в исходном PR #127: 862,4 мс → 0,9 мс на headless Godot 4.7.2. **Не является измерением нового разделённого SHA и не является GUI FPS.**

## VIS-02 / оригиналы R1–R4

`docs/visual-references/reference_manifest.json` фиксирует четыре файла 1672×941 и проверяемые SHA-256. Точный ZIP `my_shelter_visual_reference_pack_v1.zip` **найден** в ChatGPT Library: `/Мое Пространственное Убежище/my_shelter_visual_reference_pack_v1.zip`.

**Блокер:** хранилище не разрешило выдачу ZIP в виде исходных байт: `This Project file does not have an authorized raw-byte materialization path`. Попытка чтения как документа тоже завершилась ошибкой. Это **не доказательство повреждения архива**. В текущем окружении не удалось распаковать PNG, подтвердить SHA или перенести оригиналы. Статус: `VIS_NOT_RUN / BLOCKED_SOURCE_UNREADABLE`. [Issue #113](https://github.com/AndreyCokol/My_shelter/issues/113).

Уже доступный `tools/compare_visual_reference.py` содержит проверку четырёх SHA, RGB MAE, PSNR, overlay и heatmap; `tools/run_visual_checks.py` ожидает 4 настоящих захвата 1672×941. **Реальный сравнительный прогон в этом визуальном потоке не выполнялся.** При предоставлении оригинальных байт следует сверить каждую SHA по манифесту и зафиксировать один детерминированный seed/time/hero fixture, затем запускать сравнение. Без этого нет `1:1 PASS`, `PIXEL_REVIEWED`, `OWNER_ACCEPTED`.

## VIS-03 / R1 — художественный кандидат по действующим точкам взаимодействия

Ветка `work/visual-world-r1-20261109`, baseline тот же; [issue #114](https://github.com/AndreyCokol/My_shelter/issues/114). Только разрешённые пути:

- `game/scenes/worlds/world_art.gd`: дорожка из имеющейся проектной текстуры, **крыша палатки сверху, а не боковой треугольник**, стейт-зависимые грядки, 4 типа построек внутри физического отпечатка 24×22.
- `game/scenes/worlds/world.gd`: отрисовка перенесена в визуальные helper-функции, динамические данные грядок/построек берутся из runtime `snapshot(false)`; логика farm/rest/build/E/G и gameplay state не меняется.
- Каждый физический прямоугольник строительства продолжает браться из `Construction.cell_rect(cell)`, сетка 5×2 остаётся прежней. Новые дорожки — **только свободно проходимая текстура**, не дополнительные объекты и не новые коллизии. Никаких декоративных складов, ламп или костров без настоящего домена.

**Provenance:** новые элементы состоят из программных примитивов и уже имеющихся проектных `grass/path/flowers/soil` материалов. Новых сторонних PNG/шрифтов/лицензий и утверждений об их происхождении не добавлено. Лицензии существующих материалов должны быть проверены в отдельном NX-20.

**Приёмка:** сначала Linux/Windows CI, реальные screenshot R1 на том же SHA, затем проверка 1024 grid masks + реальных путей и слоёв, наконец оригинал R1 SHA → overlay/MAE → A0 review → owner. На момент подготовки этого документа `CODE_CANDIDATE / TEST_NOT_RUN / PIXEL_REVIEW_NOT_RUN`. Ни одна новая деталь не означает принятую точность 1:1.

## Границы и дальнейшие CORE/API handoff

CORE отвечает за `GameApp.preview_rest`, журнал/долговременный save, системную поставку EXE/ZIP, Windows GUI/FPS/RAM и финальное объединение. VIS изменяет только UI, artwork, сценический world и разрешённые visual/world тесты. Фиксировать новые stateful объекты «костёр/склад/мастерская» без CORE API нельзя. Сюжетный осколок — LATER, Q03–Q07 optional; схема saves v4 не изменяется.

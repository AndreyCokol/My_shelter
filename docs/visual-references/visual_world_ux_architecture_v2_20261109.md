# VIS-ARCH-02 — Архитектура визуала, процедурного мира и PC UX

**Дата:** 2026-11-09 · **Роль:** VISUAL/WORLD/UX A5 + A2 (визуальные сцены); независимый A0 — reviewer · **Статус:** DESIGN_CANDIDATE / OWNER_NOT_ACCEPTED.  
**Кодовая база для проектирования:** `a1ae8c0b68017ea4f4067a677a2d94029e1cac1d` из [PR #130](https://github.com/AndreyCokol/My_shelter/pull/130).  
**Источники требований:** [VIS-LOCK-01](../book-01/20-visual-reference-lock-redesign.md), [манифест R1–R4](reference_manifest.json), [NX-01…21 / PR #132](https://github.com/AndreyCokol/My_shelter/pull/132), [визуальный статус](../book-01/24-visual-world-status.md) из независимой R1-ветки.  
**Изменения:** только проектирование, без runtime, без новых PNG, без претензии на 1:1.

## 0. Проверенные исходные факты и границы

- `project.godot`: логическое поле **640×360**, `canvas_items`, окно 1280×720 по умолчанию; игра рассчитана на PC.
- Целевой размер сравнений владельца — **1672×941**, отношение 1672/640=2.6125 и 941/360≈2.61389. Это нецелочисленный и не совсем равный масштаб по двум осям; получить настоящий «pixel perfect» из обычного integer-NEAREST scaling нельзя без определения преобразования. Текущий тест явно меняет `Window.CONTENT_SCALE_ASPECT_IGNORE` и документирует возможное дополнение последней строки.
- Генератор `WorldLayout.VERSION=5` уже содержит **16 разных больничных физических планов**, 8 жилых этажей, 4 уличных профиля; уличная площадь ×12, внутренние ×4. Не заменять их одной нарисованной картой и не сбрасывать save v4 / совместимость v4→v5.
- R1 `game/scenes/worlds/world.gd`: `E` ферма у `(220,195)` в радиусе 58, отдых у `(400,180)` в радиусе 58, мастерская внутри `Rect2(167,239,245,91)`; физический строительный след — `Construction.cell_rect(cell)`, 5×2 ячейки. Новые изображения **не являются** новой игровой сущностью.
- Действующий визуальный [PR #138](https://github.com/AndreyCokol/My_shelter/pull/138) — художественный кандидат, с настоящими скриншотами и Linux/Windows PASS, **но не** проверенным совпадением с owner R1.
- Отдельные [PR #134](https://github.com/AndreyCokol/My_shelter/pull/134) (CORE-only `GameApp`) и [PR #135](https://github.com/AndreyCokol/My_shelter/pull/135) (VIS-only HUD/tests) дополняют друг друга. На одном интеграционном SHA их проверка ещё должна быть выполнена.
- Подлинный `my_shelter_visual_reference_pack_v1.zip` обнаружен в библиотеке ChatGPT, но из текущего окружения его **исходные байты недоступны**. Реальные SHA R1–R4 не проверены; `VIS_NOT_RUN / BLOCKED_SOURCE_UNREADABLE`. Не генерировать подмену исходников.
- [Issue #137](https://github.com/AndreyCokol/My_shelter/issues/137) — **CORE-only** гипотеза риска порядка обновления backup при precommit rename; требует воспроизведения отдельно от VIS.

## 1. Новые визуальные выводы из кода и настоящего кадра

| ID | Проверяемый факт | Риск | Статус и следующее действие |
| --- | --- | --- | --- |
| VUX-F01 | `ExplorationHUD._draw`: footer — логические `y=341..360`. `_layout`: hotbar `y=317..354` и navigation `y=330..352`. Значит пересечения с footer **13 px** и **11 px** по Y до учёта X | Текст подсказок проходит поверх hotbar/навигации; виден на настоящем R1 | `CONFIRMED_BY_CODE + SCREENSHOT`; самостоятельный VIS HUD fix с тестом геометрии |
| VUX-F02 | `GameUI._ready`: bottom-wide notice имеет offset `-58..-45`, то есть `y=302..315` при 360. При простом поднятии hotbar notice тоже начинает пересекать слоты | Простое перемещение hotbar без переразметки notice **не является решением** | `CONFIRMED_BY_CODE`; менять оба компонента одной атомарной UI-правкой |
| VUX-F03 | На R1 палатка (`Rect2(364,141,72,68)`) нарисована `WorldArt.shelter_rest`, но коллизию `StaticBody2D` из этого визуального rect не создают; точка отдыха внутри её рисунка | Игрок может пройти через воспринимаемое как сплошное сооружение; физическая палатка со сплошным коллайдером, наоборот, сломает E-подход и существующий anchor тестов | `CONFIRMED_CODE / PHYSICAL_RUNTIME_NOT_RUN`; временно маркировать как `visual-marker/walkable`; физическую модель делать отдельным проектом прохода + interaction reachability |
| VUX-F04 | `WorldArt.HOSPITAL = [teal,beige,blue,blue]`, комнаты `plan_ground` получают одинаковую текстуру по `room.kind`, а мебель `plan_details` часто выглядит как прямоугольники | Физические 16/8 уникальных геометрий **не гарантируют** уникальное художественное восприятие этажей | `CONFIRMED_BY_CODE`; детерминированные материалы/пропсы по отпечатку layout и функциональным тегам |
| VUX-F05 | В `World._draw` для hospital, house, outside всё ещё встречается `app.snapshot()`, включая проверку лута/ивента; в R1 кадр уже использует `snapshot(false)` | Лишняя полная копия `completed_actions` при перерисовке больших сцен/10k receipts | `POTENTIAL_PERF_RISK`; измерить и переводить **только read-only world rendering** на lightweight snapshot без изменения команд |
| VUX-F06 | `capture_reference_candidate` генерирует кадр нужного размера, но не сохраняет обязательную машиночитаемую фикстуру для каждого R1–R4 (seed/time/hero/HP/quest/world layout/window) | Невозможно объяснить динамические отличия и строго воспроизвести сравнение с owner | `CONFIRMED_TEST_GAP`; добавить фикстуру и маски, не объявлять 1:1 |

## 2. Разделение источника истины: WORLD → VISUAL → INTERACTION → QA

**2.1. Геометрия — единственная истина.** `WorldLayout`/`BuildingPlan` определяют `room IDs`, физические препятствия, `doors`, `portals`, `loot`, `enemy`, `spawn`, `buildings`; рендер не создаёт параллельную тайную карту коллизий. Визуальные слои не изменяют `world_seed`, `layout.version`, persist schema.

**2.2. Типизированный визуальный descriptor** — предлагаемая схема данных на стороне VIS (`game/systems/world/**` / `game/scenes/worlds/**`, только после отдельного review):

```text
VisualProp {
  stable_id: "{scene_id}/{room_id}/{source_object_id}",
  kind: "door | bed | workstation | cabinet | car | decal | ...",
  visual_rect: Rect2,
  source_geometry_id: String,
  interaction_id: String | null,
  collision_policy: "EXISTING_SOLID | FLOOR_WALKABLE | VFX_ONLY",
  render_layer: "ground | decal | wall | furnishing | actor_occlusion | light",
  material_variant: String,
  provenance_id: String
}
```

Descriptor **не становится** сохранённой gameplay state или новой механикой; он выведен детерминированно из существующих записей. Для `EXISTING_SOLID` должен находиться соответствующий physics `StaticBody2D` и пригодная точка взаимодействия. Для `FLOOR_WALKABLE` — это честная дорожка, трава, грязь, лужа или небольшой декор без обещания препятствия. Для `VFX_ONLY` — свет, пар, подсветка, анимационные частицы.

**2.3. Реальные взаимодействия.** Никакой «красивой аптеки с лутом», если медицинского контейнера нет в текущем игровом домене; допустимая подпись `DECORATIVE_ONLY` в спеке. Машина, дверь, ящик, новая постройка не могут блокировать путь только картинкой. Добавление новой логики `inventory/shelter/player/scene_router` делается **исключительно CORE-API handoff**, не VIS-правкой.

**2.4. Строгий top-down 90°.** Полы сверху, постройки через вид крыш/периметров, мебель — читаемые планы сверху, актёры — 4 кардинальных направления с единым центром 64×64 frame. Не путать это с изометрией и «видом сбоку, поставленным на плоскость».

## 3. PC UI: запланированная безопасная сетка и обязательный тест

Технический layout контракт в **логических** координатах 640×360, до отрисовки в 1280×720/1920×1080/1672×941.

| Элемент | Сейчас | Предлагаемый целевой диапазон |
| --- | --- | --- |
| footer-команды | `y=341..360` | оставить footer `y=341..360` |
| hotbar (37px) | `y=317..354` | `y=300..337`, зазор 4 px |
| navigation (22px) | `y=330..352` | `y=315..337`, зазор 4 px |
| notice (~13px) | `y=302..315` | `y=280..295`, зазор ≥5 px до hotbar |
| title/status/quest | слева сверху | сохранять, **не закрывать E-точки и actor** |
| minimap | справа сверху | сохранять, не пересекать radial и модальные окна |

**Важно:** это только layout-предложение, а не утверждённый художественный кадр. Реальный тест должен вычислять `get_global_rect()` видимых HUD Control, область footer (`Rect2(0,341,640,19)`), проверить `intersects == false` для hotbar/navigation/notice во всех трёх физических режимах; отдельно проверить реальные координаты hitbox, clipping/footer, hover/focus, анимацию Alt+Tab, Esc, Left Ctrl и переключение режимов. Нужна симуляция указателя в активном HUD, чтобы клики не проходили сквозь UI; `mouse_filter = IGNORE` у контейнера нельзя считать единственным доказательством безопасности.

**Физический масштаб:** на 1672×941 использовать документированное точное mapping из 640×360 с понятной политикой дробного масштаба / possible bottom padded row. Если owner R1 нарисован в другой scale density, сравнение MAE не может автоматически принуждать одинаковую ширину каждой буквы; требуется зафиксировать разрешённое преобразование, затем пересматривать визуал, а не прятать несоответствие маской.

## 4. Художественная система двух миров

**R1 (убежище):** материалы травы, земли, древесины, тёплый штукатурный свет; различимость следов ходьбы, дорожек, грядок (empty/growing/ripe/spoiled), отдыха, рабочих ячеек, действующих объектов и жителей. Сначала убрать конфликт UI, согласовать условную палатку/коллизию; затем усилить детализацию без новых фиктивных интерактивных зданий. Костёр/склад — **только** если уже существует функциональный игровой node либо owner/CORE одобрит механику; иначе явный decorative label.

**R2 (улица):** мокрые и разрушенные поверхности, **лужи/следы как walkable decals**, холодные серо-зелёные/синие цвета, заросли, освещение/световые конусы не прячут NPC/loot, реальная машина только с препятствием из layout. Фасады должны быть согласованы с `layout.exits`. Не заменять route на круговой маркер или невидимые телепорты.

**R3 (больница):** настоящий `floor_plan` определяет коридоры, палаты/аптеку/процедурную, лестницы и двери; на каждый `room.kind` назначать функциональный материал и отличающиеся prop rules. Лестницы открывают существующий `portal`, лут доступен без прохода через стену. **16 физических floor fingerprints + 16 visual signatures**, а не одни и те же картинки с другой надписью.

**R4 (жилой этаж):** зоны кухни/спальни/санузла/коридора строго исходят из `plan.rooms`. Кровати/шкафы/сантехника из `plan.furniture` с реальными obstruction rectangles и внятным top-down видом; декоративный мелкий беспорядок допускается как floor decal. **8 уникальных визуальных подписей**, проход/лут/возврат до и после load.

**Общее:** 128×128 исходные floor textures / 64×64 actor frames сохраняются на отдельных арт-слоях. Variant вычислять из устойчивого hash (`world_seed, scene_id, room_id, purpose`), а не случайного генератора во время `_draw()`; повторный вход, загрузка и тот же seed должны дать идентичный арт. Art pipeline: source license/provenance ID, pixels-per-unit и filtering, generated deterministic placement, physics cross-check, real screenshot, A0/owner.

## 5. R1–R4 pixel audit protocol — чтобы сравнение было воспроизводимым

1. **Source integrity:** только 4 исходных байтовых PNG 1672×941 с SHA-256, точно совпадающим с `reference_manifest.json`; неподлинный ZIP → `BLOCKED_SOURCE_MISSING/UNREADABLE` или `SHA_MISMATCH`.
2. **Fixture:** рядом с каждым снимком сохранить JSON: commit SHA, Godot version, scene_id, world_seed, layout generator v, actor frame/facing/position, camera/zoom, time, HP/dodge/XP/currency, equipped items, quest, NPC/enemy/loot state, open panels, viewport size и масштабирование.
3. **Identity:** одинаковые seed/position/game state/time для переснимаемой игровой сцены; если owner original не раскрывает state — задать согласованный статический target, перечислить недоступные измерения как uncertainties.
4. **Render/capture:** отдельные реальный Godot native PNG 1280×720, 1920×1080, 1672×941; source и screenshot не масштабировать молча. Любой padding, crop, letterbox и resize сохранять в transform JSON.
5. **Diff:** сравнивать full-frame RGB MAE/PSNR + области `title/status/quest/minimap/hotbar/footer` **и world/scene key regions**, включая R1 construction; сохранённые overlay+heatmap. Маски должны быть JSON rects с причиной и покрытием маски (%), а **не** автоматически закрывать весь отличающийся мир.
6. **Acceptance:** `CODE_CANDIDATE → CI_PASS → PIXEL_REVIEWED → A0_REVIEWED → OWNER_ACCEPTED`; числовые пороги/допуски утверждает владелец после первого корректного диффа. **Результат только про отчёт**, не `1:1 PASS`, пока не выполнены все зависимости.

## 6. Минимальная проверочная матрица (следующие PR)

| ID / владелец | Проверяемая работа | Доказательство / DoD |
| --- | --- | --- |
| VUX-01 / VIS-A5 | Починить footer, hotbar, nav, notice, проверку input-through | Встроенный test пересечений = 0; 3 desktop resolutions, real PNG, Left Ctrl/E/G неизменны |
| VUX-02 / VIS-A5+A0 | Exact visual fixture и JSON masks + diff R1–R4 | 4 source SHA, 4 deterministic game captures, 4 overlays+heatmaps, full-frame + 7+ ROIs; blocked source не маскировать |
| VUX-03 / VIS-A5/A2 | R1 collision/visual marker контракт + настоящее crop/build visual states | Контроль "непроходимый" декор vs physics, 1024 masks, plot state screenshot, E farm/rest/workshop |
| VUX-04 / VIS-A2+A5 | R2 world material/decal/portal layering | 4 physical street profiles, 4 visual signatures, path/loot/AI, screenshots по ≥4 seed |
| VUX-05 / VIS-A2+A5 | R3 hospital room-specific art | 16 физически уникальных floors+16 visual signatures, stairs/doors/cache/LOS, path after reload |
| VUX-06 / VIS-A2+A5 | R4 apartments room-specific art | 8 unique floor visual signatures, door colliders + furniture/loot/reload |
| VUX-07 / VIS-A5 | 64×64 art animation audit: idle/walk/attack/hit/dodge/death | 4 directions, align/silhouette/hit windows, natural survivor gait; gameplay event integration via CORE-API |
| VUX-08 / VIS-A5+A0 | 13 модальных окон, прокрутка, focus/keyboard, hover и подсказки | Тесты keyboard+mouse, 3 sizes, no stuck pause, no text clipping, meaningful disabled states |
| VUX-09 / VIS-A5→CORE | Сводный provenance + render/LOD cost evidence | SHA/source/license per asset, no unlicensed external imports; FPS/RAM/window soak делает CORE, не VIS |

**Отдельный инженерный gate:** CORE-only [PR #134](https://github.com/AndreyCokol/My_shelter/pull/134) + VIS-only [PR #135](https://github.com/AndreyCokol/My_shelter/pull/135) запускаются на **одном интегрированном SHA**, затем повторяются Linux/Windows/docs. Визуальные PR по R1/R2/R3/R4 не должны вносить в чужой API файлы и не должны объединяться в `main` без проверяемой независимой приёмки.

## 7. Приоритет исполнения без взаимных конфликтов

1. **P0:** VUX-01 layout (наблюдаемая UI ошибка), CORE совместно проверяет #134+#135. Параллельно A0 добивается доступности оригиналов; любой отказ документируется.
2. **P0:** VUX-02 source/fixture/audit — обязательный для утверждения 1:1, но не блокирует самостоятельную художественную разработку.
3. **P0:** VUX-03 R1 фактические ферма/отдых/строительство/коллизии; затем R2 → R3 → R4 в отдельных PR, каждый со своим screenshot/provenance.
4. **P1:** VUX-07 персонажи, VUX-08 углубление HUD/окон, VUX-09 эффекты/лицензии/производительность.
5. **Gate:** A0 независимый просмотр, owner 1:1 решение и общий CORE Windows GUI + FPS/RAM + restore/recovery проверки. Никакого самопровозглашённого `G0/G4 APPROVED`.

**Не делать:** заново писать Godot state/систему сохранений, сливать чужие PR, добавлять большие декоративные районы без физики, рисовать статический screenshot вместо сцены, расширять сюжет до Q03–Q07 обязательными квестами, придумывать survival-статы и менять `schema-v4`.

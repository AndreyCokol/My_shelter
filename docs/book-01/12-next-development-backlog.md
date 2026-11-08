# 12 — План работ до полноценного закрытого прототипа

**Версия:** 2026-11-08 · **Основание:** решения владельца OD-01..OD-12, [PR #31](https://github.com/AndreyCokol/My_shelter/pull/31) — процедурный прототип, [Issue #4](https://github.com/AndreyCokol/My_shelter/issues/4) — G0 ещё открыт. **План — очередь задач, не отметки об исполнении.**

## Порядок приоритетов

| Этап | GitHub Issue / PR | Владелец | Что считается готовым |
|---|---|---|---|
| M0: контракт и безопасность | [#36](https://github.com/AndreyCokol/My_shelter/issues/36), [#4](https://github.com/AndreyCokol/My_shelter/issues/4), [#14](https://github.com/AndreyCokol/My_shelter/issues/14) | A1 + A5, владелец для G0/видимости | Единственный согласованный contract v1.5+/schema4 и точный SHA; осознанная политика PRIVATE исходников |
| M1: право игрока вернуться домой | [#37](https://github.com/AndreyCokol/My_shelter/issues/37) / [PR #39](https://github.com/AndreyCokol/My_shelter/pull/39) | A1 core + A5 весь UI + A2 QA | FR-05: shelter всегда доступен по G/кнопке, бой/первая победа не gate; точный return position и HP после save/load; CT-48..52 |
| M1: боевые/сейв блокеры | [#33](https://github.com/AndreyCokol/My_shelter/issues/33), [#34](https://github.com/AndreyCokol/My_shelter/issues/34) | A2; A1+A3 | Нельзя бить через стены; изменения баланса не убивают сохранения |
| M1: производительность и история | [#35](https://github.com/AndreyCokol/My_shelter/issues/35) | A1 + A0 review | Замеры затрат кадра и памяти, bounded notifications, безопасная политика receipts |
| M2: бой/телепорт | [#41](https://github.com/AndreyCokol/My_shelter/issues/41) | A2 | Реальный бой с LOS, отступлением и недублируемыми наградами |
| M2: развивающаяся песочница | [#42](https://github.com/AndreyCokol/My_shelter/issues/42) | A3 | Ферма/склад/еда/труд без softlock, сценарии 3/7/14 дней |
| M2: мотивирующий сюжет | [#43](https://github.com/AndreyCokol/My_shelter/issues/43) | A4 | Q01–Q02 как обучение, Q03–Q07 необязательны, добровольные NPC и сохранённое consent |
| M2: помещения и переходы | [#44](https://github.com/AndreyCokol/My_shelter/issues/44) | A2 + A5 | Двери/лестницы/квартиры достижимы, процедурные семена и возвраты детерминированы |
| M2: управление и радиальное меню | [#40](https://github.com/AndreyCokol/My_shelter/issues/40) | **A5 пишет весь UI**, A0 проверяет | Left Ctrl открывает радиальное меню, UI/G/пауза/keyboard focus не конфликтуют |
| M3: человекопригодность игры | [#45](https://github.com/AndreyCokol/My_shelter/issues/45), [#13](https://github.com/AndreyCokol/My_shelter/issues/13) | A5 + независимый A0 | Ручной Windows GUI, проверка 15–35 минут, две разные визуальные атмосферы, измеренный FPS и память |
| M3: личная поставка | [#46](https://github.com/AndreyCokol/My_shelter/issues/46), [#29](https://github.com/AndreyCokol/My_shelter/issues/29) | A5 + A0 | Офлайн Windows .exe, законные ассеты, приватное распространение, rollback/backup |

## Правило блокирующих зависимостей

1. **Сначала M1.** Пока shelter transition, сохранения или hit-through-walls не исправлены, нельзя считать игровой маршрут P0 готовым только по зелёному CI из предыдущего PR.
2. **M2 можно вести параллельно по зонам ownership:** A2 Combat/World, A3 Farm, A4 NPC/Story, A5 весь UI, A1 контракты и core; A0 — вертикальное ревью, независимое от авторства. Изменения общих DTO через A1 и A5.
3. **M3 не равен публикации.** Сборка локальная/закрытая. Если GitHub repository остаётся PUBLIC, проверять содержимое каждого коммита и лицензии ассетов; не выкладывать защищённые материалы.
4. **G0 не перескакивать:** owner product decisions записаны, но contract SHA и merge остаются на [Issue #4](https://github.com/AndreyCokol/My_shelter/issues/4). Отдельные разрешения на код не означают blanket G0 approved.

## Матрица контрольной приёмки

| Контроль | Обязательная проверка | Доказательство |
|---|---|---|
| Сборка | Godot 4.7.2 stable import, headless/test, native Windows x64 export/start | CI URL, exact SHA, 0 failures |
| Бой | Настоящая physics collision/LOS, dodge, defeat, Г-escape посреди атаки | GDScript E2E, A2 reviewer |
| Мир | 128+ seed, 4 больницы × 4 этажa, уникальные квартиры, реальные входы/выходы; 24+ перехода | Навигационная проверка, screenshots, сохранение/загрузка |
| Хозяйство | Два режима времени, один календарь, нет дублей и softlock | A3 fixtures + replay tests |
| Управление | G без first_enemy gate, Left Ctrl radial, Esc/modal/recovery без потерянных pause tokens | A5 UI E2E + A0 |
| Игровой UX | Понятный первый маршрут 15–35 минут, свободная игра после Q02 | Человеческий сеанс с замером, не headless тест |
| Лицензии | Каждому включённому ассету разрешён конкретный способ использования | лицензии/credits/release checklist |

## Доказательства на старте плана

- До новой функции: [PR #31 Linux CI](https://github.com/AndreyCokol/My_shelter/actions/runs/42373276704) 410 проверок PASS и 19 render checks; [Windows](https://github.com/AndreyCokol/My_shelter/actions/runs/42373276640) 410 и headless exe PASS.
- PR #39 содержит новый P0 доступ к убежищу и регрессионные проверки; **его конкретный последний CI должен быть успешным до отметки IMPLEMENTED/TESTED**.
- [PR #32](https://github.com/AndreyCokol/My_shelter/pull/32) — статические замечания A0; задачи #33–35 ещё требуют исправлений.

**Готовность к полноценной эксплуатации:** не ранее фактического прохождения M1, проверки M2, Windows GUI/UX и целевого принятия A5/владельцем. Статусы задач обновляются по реальным коммитам, тестам и PR, а не количеством открытых Issues.

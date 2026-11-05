# 08 — G0 Decision Record / реестр решений владельца и технических проверок

**Дата:** 2026-11-05 · **Статус:** `PRODUCT_DECISIONS_ACCEPTED / TECHNICAL_G0_PENDING` · **Авторитет:** явные решения владельца в диалоге проекта; запись в GitHub — воспроизводимая транскрипция, но не утверждение данного commit SHA и не разрешение начинать код.

## 1. Решения владельца — УЖЕ ПРИНЯТЫ, не запрашивать повторно

| OD | Обязательное решение | Эффект |
|---|---|---|
| OD-01 | **Песочница с сюжетными заданиями** | Нет обязательного линейного маршрута после короткого onboarding |
| OD-02 | **Реальное время: атака, уклонение, оружие** | A2 делает реальную боевую механику и InputMap |
| OD-03 | **Два варианта ожидания урожая** | Естественное игровое время + отдых через тот же GameClock |
| OD-04 | **Еда нужна для заселения; количество определяется балансом** | Нет жёсткой нормы «2 картофелины»; parametric `arrival_food_requirement` |
| OD-05 | **A5 лично разрабатывает весь UI** | Исключительный владелец UI, плюс главный координатор и интегратор |
| OD-06 | **Свободная игра по мотивам произведения** | Литературная хронология/цифры — reference, не обязательный дизайн |
| OD-07 | **Взрослые и неоднозначные темы существенно переработать для широкой аудитории** | Добровольные договоры, без эксплуатационной механики и откровенных сцен |
| OD-08 | **Весь эпизод пространственного осколка перенести на поздний этап** | `FR-25=LATER`; не входит ни в MVP, ни в текущую P1/P2 кампанию |
| OD-09 | **Первый MVP — короткий вертикальный срез 15–35 минут** | Проверяемая гипотеза UX; независимая свободная игра после маршрута |
| OD-10 | **Только личный закрытый прототип** | Никаких публичных релизных обязательств и публикации чужих материалов |
| OD-11 | **A0 — вертикальный сверщик, консультант, агент поддержки и независимый reviewer A5** | Не главный, не владеет чужими файлами, не новый обязательный gate |

**Статус OD-01–OD-11: APPROVED BY OWNER (продуктовая постановка)**. Для них не требуется повторного вопроса. Реализация требует отдельного принятых контрактов и соблюдения G0.

## 2. Технические решения D-01..D-19

| ID | Результат / кандидат | Текущий статус | Кто закрывает |
|---|---|---|---|
| D-01 | Godot **4.7.2-stable** + GDScript, Windows x64, export templates; версия опубликована 2026-08-18 | `SELECTED_ON_PAPER / RUNTIME_NOT_TESTED` | A1 GUI/headless/Windows smoke в G1a, A5 audit |
| D-02 | 2D top-down pixel-art, 32×32 tile начальный вариант; nearest-neighbor; UI масштабируется отдельно | `DESIGN_CANDIDATE` | A5 screenshot/визуальный тест; уточнение без владельца |
| D-03 | Real-time бой: ходьба, атака, dodge, оружие, модальное UI ставит на паузу | `OWNER_CORE_APPROVED / UI_DETAILS_DELEGATED` | A2+A5 |
| D-04 | InputMap actions движение/атака/уклонение/взаимодействие/убежище/меню/пауза | `DELEGATED` | A1/A2/A5 |
| D-05 | Один int `GameMinute`, естественное время и safe rest; коэффициент времени конфигурируется | `OWNER_MODES_APPROVED / NUMBERS_DELEGATED` | A1/A3/A5 |
| D-06 | Картофель 72/12 **как литературная фикстура**, не hardcode, эффективность из active rules | `CONFIG_CANDIDATE` | A3+A5 баланс |
| D-07 | Еда по `arrival_food_requirement`; добровольное согласие и atomic reserve+resident | `OWNER_PRINCIPLE_APPROVED / NUMBERS_DELEGATED` | A1/A3/A4/A5 |
| D-08 | Один обычный зомби полноценно в P0; другие типы P1 | `SCOPE_CANDIDATE` | A2+A5 |
| D-09 | **Единственный нормативный кандидат:** [05-integration-contracts.md](05-integration-contracts.md) (commands, result, post-commit, receipts, error codes) | `AWAITING_REVIEW_AND_SHA` | A1–A5, A0 reviewer |
| D-10 | Локальное версионированное JSON save/backup, reset on corruption запрещён | `AWAITING_REVIEW` | A1/A5 |
| D-11 | A1 core, A2 combat, A3 farm, A4 narrative, **A5 ALL UI** | `OWNER_ASSIGNMENT_APPROVED` | A5 координация |
| D-12 | **A5 chief** (техническая координация/общая интеграция); A1 владелец core; **A0 support + independent verification** | `OWNER_ASSIGNMENT_APPROVED` | A5/A1/A0 |
| D-13 | Свободная песочница, Q01/Q02 onboarding; Q03–Q07 необязательны для базовой симуляции | `OWNER_INTENT_APPROVED / QUEST_DESIGN_CANDIDATE` | A4+A5 |
| D-14 | Контент для широкой аудитории, добровольные соглашения; **закрытый** прототип, правовой gate до публикации | `OWNER_INTENT_APPROVED / EDITORIAL_DETAILS_DELEGATED` | A4+A5 |
| D-15 | Unit/contract/E2E, real headless & Windows export, 60 FPS target only after measurement | `TEST_DESIGN_READY / NOT_RUN` | A1/A5/A0 |
| D-16 | 15–35 мин целевой первый цикл; предварительно обязательный внутренний smoke, внешние плейтесты не блокируют первый запуск | `OWNER_DURATION_APPROVED / UX_NOT_MEASURED` | A5/A0 |
| D-17 | Один [консолидированный PR #7](https://github.com/AndreyCokol/My_shelter/pull/7), старые #1/#2/#5/#6 закрыты без merge; SHA после review | `CONSOLIDATED / REVIEW_PENDING` | A5+A1/владелец |
| D-18 | **ВЕСЬ** осколок LATER, ни P1, ни P2 не обязательны | `OWNER_APPROVED` | A4+A5 |
| D-19 | Только частная демонстрация; распространение и все публичные релизные задачи out of scope | `OWNER_APPROVED` | Владелец |

**Проверенный публичный источник версии движка:** https://godotengine.org/download/archive/4.7.2-stable/ . Существование релиза подтверждено; **локальная установка/совместимость плагинов/экспорт не подтверждены**. Версию не повышать автоматически до 4.8 beta.

## 3. Что означает APPROVED vs CANDIDATE

- `OWNER_APPROVED` — владелец явно выбрал принцип/направление.
- `DELEGATED` — мелкая техническая конкретика остаётся за A5+A1–A4 и требует записи в ADR/PR, но не нового продуктового голосования.
- `CANDIDATE` — документация готова к review, контракт **не принят**.
- `NOT_RUN`/`RUNTIME_NOT_TESTED` — не выполнен реальный запуск, не заменять на PASS.
- `G0_APPROVED` возникает **только** после ссылки на решение владельца, фиксации **фактического SHA** согласованного контракта/PRD/плана, review A1–A5, разрешения конфликтов документации и merge. A0 дополнительный консультант без обязательной подписи.

**Не изобретать запреты:** технические предпочтения A5/рекомендации A0 не должны создавать дополнительные owner gates сверх G0. После G0 A1/A5 проводят необходимые технические проверки в G1a/G2/G4.

## 4. Контрольный список оставшихся действий для G0

- [x] Приняты 10 продуктовых решений + роль A0, включая разграничение A5/A1.
- [x] В одной консолидированной ветке устранить жесткий сюжетный порядок, 2 картофелины, осколок, конкурирующие роли UI (проверить статическим аудитом).
- [x] Единый кандидат API, state, save и time размещён в `05`; отдельный `07` не вводится как второй нормативный контракт.
- [ ] Действительный review A1/A2/A3/A4/A5 по своим интерфейсам (реальные комментарии/ссылки; один исполнитель не выдаёт себя за 5 запущенных агентов).
- [ ] Независимое review A0/A1 собственных UI интерфейсов A5 при наличии соответствующего исполнителя; если отсутствует — явный `REVIEW_NOT_PERFORMED`.
- [ ] Технический конфиг baseline (tile/time/food) зарегистрирован A5/A1 в ADR или issue; числовые значения допускается дорабатывать после UX.
- [x] Старые PR #1/#2/#5/#6 закрыты без merge, консолидированный PR #7 — единственный открытый кандидат.
- [ ] PR #7 прошёл независимое документальное review A1–A5, все находки разрешены; SHA заморожен.
- [ ] Владелец явно подтверждает **финальную редакцию по SHA**; Issue #4 переведён в `G0 APPROVED` только после этого.

### Конкретные review Issues — ещё не выполнены

- [A1 #8](https://github.com/AndreyCokol/My_shelter/issues/8) — контракты, commit/Save; [A2 #9](https://github.com/AndreyCokol/My_shelter/issues/9) — Combat/Input/softlock; [A3 #10](https://github.com/AndreyCokol/My_shelter/issues/10) — Clock/Farm/Food.
- [A4 #11](https://github.com/AndreyCokol/My_shelter/issues/11) — добровольный NPC и optional quests; [A5 #12](https://github.com/AndreyCokol/My_shelter/issues/12) — архитектура, UI, integration; [A0 #13](https://github.com/AndreyCokol/My_shelter/issues/13) — независимое вертикальное ревью и рекомендации A5.
- **Не считать создание Issues запуском 6 процессов или одобрением G0**. Реальное review — комментарий с конкретными findings/evidence.
- Новые технические поправки в [11](11-technical-decisions-and-handoff.md) и [10](10-qa-acceptance-matrix.md) включают разделение игрового времени/боевых кадров, защиту от softlock и локальную документационную CI. CI PASS **не заменяет** Godot, Windows, A0 review или G0 owner approval.

## 5. После G0

G1a — существующий и запускающийся `project.godot`, CLI/GUI и Windows export templates, mocks/contract tests, CI. G1b — параллельные A2/A3/A4 + **весь UI A5**, A0 независимое ревью. G2/G3/G4 — полные E2E по [10-qa-acceptance-matrix.md](10-qa-acceptance-matrix.md). Ни один пункт про код нельзя считать закрытым, пока код не создан и тесты не прошли.

## 6. Evidence record — заполнить **фактами**, не заглушками

```text
Owner decision: OD-01..OD-11 accepted 2026-11-05 (this conversation)
Consolidated PR URL: https://github.com/AndreyCokol/My_shelter/pull/7
PRD SHA: <real SHA after final review>
Contract SHA: <real SHA after final review>
Plan SHA: <real SHA after final review>
A1–A5 reviewers: NOT_REVIEWED; issues #8 #9 #10 #11 #12 created for scoped review
A0 reviewer: NOT_REVIEWED; issue #13 created for independent review
Owner freeze approval link: <actual Issue/PR comment, otherwise PENDING>
Gate status: G0_BLOCKED until above are verified
```

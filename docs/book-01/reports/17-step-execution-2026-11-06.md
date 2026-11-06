# Последовательное исполнение 17 шагов

Основание: прямое поручение владельца выполнить весь план; один исполнитель Codex, без фиктивного назначения независимых подписантов. База e8f9e6b, Issue #27. Интеграционная ветка integration/playable-prototype-20261106 включает весь стек #7/#16/#18/#20/#22/#24/#26 по ancestry; main не изменяется.

1. Авторская повторная проверка стека: baseline 153 assertions PASS, docs PASS. Независимый review NOT_PERFORMED, формальное согласование G0 не присваивается.
2. Устаревший header QA исправлен. Далее статусы обновляются по фактическим проверкам.

Шаги 3–17: IN_PROGRESS/NOT_RUN до записи доказательств. Подтверждение одним автором не считается независимым review. Целевые Windows и UX 15–35 минут требуют фактической проверки.

## Промежуточная реализация

Шаги 3–11: gameplay schema v3, оригинальные catalogs, actor/enemy real-time controller, четыре PackedScene мира, возобновляемые семена, два поля, полив/рост/порча, атомарный урожай, optional quests, добровольные соглашения и конкретные food reservations. Проверки domain suite 41 + edge suite 32 PASS. Runtime suite 32 PASS: реальное движение/удары/cooldowns/dodge, смены миров, весь цикл до двух жителей, save/load health/position, UI pause/focus ownership и reopen.

Шаг 12: русский UI всех основных панелей подключён через команды. Шаг 13: исходные геометрические рисунки, сторонние ассеты не используются; графическая валидация продолжается отдельно. Шаг 14: scripted E2E на реальном SceneTree PASS, это не human UX acceptance.

Шаг 15: REVIEW_NOT_PERFORMED — один автор не может независимо одобрить собственные изменения. Шаг 16: release export PE32+ Windows x64 и Linux ELF создан. Фактический native Windows запуск ещё NOT_RUN. Шаг 17: целевые 15–35 минут не измерены, первый короткий runtime smoke не подтверждает баланс.

## Ограничение графической среды

Попытка запуска GUI в среде исполнения не получила X11/Wayland display. Дополнительно проверен разрешённый native desktop: он имеет отдельную файловую систему, не видит ни рабочий каталог, ни /tmp, ни /mnt/data этой сессии; GitHub clone в его сетевом окружении недоступен. Поэтому нельзя получить доказательные скриншоты/визуальную оценку именно этой сборки. CUA завершён с явным ограничением. Headless SceneTree/UI-layout tests — отдельное доказательство, не замена визуальному PASS. Подготовлен run_visual_tests.gd для среды с display.


## Точное состояние 17 пунктов после реализации

| № | Работа | Статус и доказательство |
|---|---|---|
| 1 | Ревью/объединение | PARTIAL: весь стек включён в integration branch по ancestry, авторская проверка и regression PASS; main/формальная приёмка/review не подменяются |
| 2 | Документы | PASS: заголовок QA исправлен, контракт v1.5, карта и README актуализированы |
| 3 | Игровые состояния | IMPLEMENTED/PASS: schema v3, негативные domain/link/load тесты |
| 4 | Каталоги | IMPLEMENTED/PASS: правила/имена/таймеры/food config; баланс — кандидат |
| 5 | Герой/бой | IMPLEMENTED/PASS: реальные physics frames, melee/cooldowns/dodge и уникальный unlock |
| 6 | Исследование/возрождение | IMPLEMENTED/PASS: четыре PackedScene, ресурсный cooldown/save, safe respawn |
| 7 | Убежище/ферма | IMPLEMENTED/PASS: два поля, посадка/полив, natural time/rest |
| 8 | Урожай/хранение | IMPLEMENTED/PASS: atomic harvest, capacity rollback, reserved transfer |
| 9 | Время | IMPLEMENTED/PASS для текущих доменов: общий planner, real crop deadlines, pure preview; будущие интерактивные quests требуют adapter |
| 10 | Квесты | IMPLEMENTED/PASS: Q01–02 и optional tracking Q03–07, независимый sandbox |
| 11 | Жители/еда | IMPLEMENTED/PASS: contact/decline/consent/AWAITING_SUPPLIES/recruit, reserve/consume 1 и 3 units, конкретный состав receipt |
| 12 | UI | IMPLEMENTED/headless PASS: основные русские панели, pause ownership, focus/Escape, reopen; visual acceptance отдельно |
| 13 | Визуальная проверка | PARTIAL: оригинальные рисунки/лицензии готовы, UI layout construction PASS; скриншоты и визуальная оценка NOT_RUN из-за недоступности графической среды для этих файлов |
| 14 | Сквозная интеграция | SCRIPTED PASS: actual SceneTree/actors/commands через два жителя и save/load; human acceptance не заявлена |
| 15 | Независимое ревью | NOT_PERFORMED: один автор; действительный не-автор пока не доступен/не назначен |
| 16 | Windows | PASS (headless): export PE32+ x64, все 260 assertions и запуск release .exe на Windows Server 2025 через CI; GUI acceptance отдельно |
| 17 | Приёмка MVP | PARTIAL: технический smoke есть; целевые 15–35 минут/человеческая понятность NOT_MEASURED, G4 не пройден |

Итого Linux: 21 core + 31 campaign + 27 router + 39 event + 35 calendar + 41 gameplay + 32 edge + 34 runtime = **260 assertions**, 0 failures. [Полный лог](17-step-checks-4.7.2-linux.log). Runner ограничивает время и проверяет ошибки/утечки; suite включены в GitHub CI.

Устранённые при проверке дефекты: дробный Clock терял точность JSON (full_precision=true), cross-validator обращался к items до проверки формы (перенесён после общего валидатора), сохранение могло менять configured capacity (проверяется против каталога), зарезервированный стек расходовать нельзя, joined receipt теперь сохраняет/проверяет реальный состав пищи; modal Escape очищает focus, Space после меню не активирует старую кнопку.

Архив Windows содержит только executable, инструкцию, SHA256 и Godot engine/component notices. В GitHub Actions бинарник не публикуется как artifact/release. Исходники/логи оригинальной реализации находятся в PR #28; защищённый контент не добавлялся. Не считать все 17 принятыми из-за объёма кода или зелёного CI.


## Native Windows evidence и артефакт

На коде `27eee756368cef9d675bc6d55bfac1f2768077a7` все три GitHub workflow SUCCESS: documentation, Linux core/gameplay и Windows prototype validation. [Windows run 42198787927](https://github.com/AndreyCokol/My_shelter/actions/runs/42198787927), job 127828614304. На Microsoft Windows Server 2025 прошли те же 260 assertions, затем Windows release export и запуск собранного MyShelter.exe с `--headless --audio-driver Dummy --quit-after 10`; получен startup marker `Playable prototype initialized; schema v3`, exit без script errors. [Выдержка native Windows лога](17-step-windows-evidence.log). Это реальная Windows проверка headless, а не Wine/Linux и не GUI acceptance Windows 10/11.

Windows архив: MyShelter_Windows_x64_prototype_2026-11-06.zip, 38 187 766 bytes, CRC всех entries PASS. SHA256 архива: `62f2bb83bd6faf9b6fbd68e88ddc54dfc9c3b11b775a3f22604be8f7b5e32b46`. Он содержит MyShelter.exe, READ_ME_RU.txt, SHA256.txt, GODOT_NOTICES.txt. Локальный Linux release также запущен headless с правильным startup marker. Бинарный код соответствует tested SHA, последующие изменения этого отчёта не меняют сборку.

Оставшиеся реальные блокеры завершения всех 17: независимый не-автор для review/приёмки PR; доступная графическая среда с файлами проекта для визуальной проверки и human UX-сеанса; измерение/доработка баланса до целевых 15–35 минут. Без этих доказательств G4 и весь список не объявляются завершёнными. Разработка разрешённого кода и доступные проверки выполнены; ожидание внешнего reviewer не маскируется бесконечными повторными тестами.

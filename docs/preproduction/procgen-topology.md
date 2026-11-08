# NEW-02/05 — спецификация процедурных локаций
Статус DRAFT.
Алгоритм: построить связный graph rooms/corridors/stairs/entrances/streets → разместить footprint в grid → вставить реальные двери и paired portals → flood-fill по collision_grid и обязательным целям → наполнить ассетами без блокировки проходов → сохранить seed, profile, content_version, topology fingerprint и runtime overrides.
API proposal: generate(seed, profile_id, content_version, attempt_index) → ok, level_graph, geometry, portal_registry, spawn_cells, fingerprint, errors.
Каждый portal имеет counterpart_id, destination_level_id и безопасную destination_spawn_cell. Портал здания должен корректно соединять подъезд с улицей и обратно; квартира связана с подъездом. При неудаче ограниченное число повторов и диагностическая ошибка, не непроходимая карта.
Масштаб улиц ×12, зданий/больниц ×4 относительно baseline, который ещё нужно формализовать. Четыре больницы по четыре отличных этажа = минимум 16; разные seeds без проверки fingerprint не гарантируют уникальность.
Тесты PROC-01: детерминизм seed/version. PROC-02: 1000 seed, достижимость обязательных комнат. PROC-03: обратимость порталов. PROC-04: безопасный fail. PROC-05: сохранение и восстановление графа. Все тесты пока PLANNED.
Владение: A2 город/больницы/квартиры; A3 убежище; A1 портал/seed/SceneRouter; A5 визуализация; A0 QA для A5.

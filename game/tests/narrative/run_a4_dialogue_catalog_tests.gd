extends SceneTree

# Standalone, non-UI validation of an ORIGINAL candidate dialogue catalog.
var checks: int = 0
var failures: int = 0
const PATH := "res://game/data/narrative/dialogues_ru_candidate.json"

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS " + label)
	else:
		failures += 1
		push_error("FAIL " + label)

func run() -> void:
	check(FileAccess.file_exists(PATH), "A4 Russian dialogue catalog exists")
	if not FileAccess.file_exists(PATH):
		quit(1)
		return
	var parser := JSON.new()
	var raw: String = FileAccess.get_file_as_string(PATH)
	var parse_error: Error = parser.parse(raw)
	check(parse_error == OK, "dialogue source is valid UTF-8 JSON")
	if parse_error != OK:
		quit(1)
		return
	var catalog = parser.get_data()
	check(catalog is Dictionary, "catalog root is a dictionary")
	if not catalog is Dictionary:
		quit(1)
		return
	check(catalog.get("locale") == "ru" and catalog.get("format_version") == 1,
		"language and candidate schema explicitly declared")
	check(catalog.get("scope") == "A4_P0_ORIGINAL_DRAFT",
		"dialogue source must be recognized as draft, not canonical story")
	var quests = catalog.get("quest_lines")
	check(quests is Dictionary, "quest texts collected by quest ID")
	if not quests is Dictionary:
		quit(1)
		return
	var ids: Array = quests.keys()
	ids.sort()
	check(ids == ["Q01", "Q02", "Q03", "Q04", "Q05", "Q06", "Q07"],
		"only seven P0 quest IDs included: no spatial shard")
	for id in ids:
		var record = quests[id]
		check(record is Dictionary and record.get("intro") is String and record.get("completed") is String
			and not record.intro.strip_edges().is_empty() and not record.completed.strip_edges().is_empty(),
			"quest " + id + " has both complete Russian strings")
	check(str(quests.Q02.intro).contains("уже доступно") and str(quests.Q02.intro).contains("G"),
		"Q02 never asserts that shelter unlocks after first kill")
	check(str(quests.Q03.intro).contains("не нужно следить"),
		"optional farm text explains the world works without active quest")
	check(str(quests.Q06.intro).contains("возможность отказаться"),
		"recruitment tutorial offers voluntary refusal")
	var npc = catalog.get("npc_lines")
	check(npc is Dictionary and npc.size() == 12,
		"NPC dialogue has explicit states for contact, consent, waiting and expedition")
	if npc is Dictionary:
		for key in npc:
			check(npc[key] is String and not str(npc[key]).strip_edges().is_empty(),
				"NPC dialogue key " + str(key) + " has a nonempty line")
		check(str(npc.get("declined", "")).contains("Пока нет"),
			"decline is explicitly represented and not a game-over")
		check(str(npc.get("accepted_waiting", "")).contains("припасы"),
			"consent and supply check are separate")
		check(str(npc.get("expedition_observation", "")).contains("компьютера убежища")
			and str(npc.get("expedition_observation", "")).contains("наблюдать"),
			"future expedition monitoring is described through the shelter computer")
		check(str(npc.get("expedition_observation", "")).contains("Телепортация")
			and str(npc.get("expedition_observation", "")).contains("недоступна"),
			"expedition monitoring text never promises teleport")
	check(not raw.to_lower().contains("осколок"),
		"later spatial shard arc does not leak into P0 dialogues")
	print("A4 DIALOGUE CATALOG TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

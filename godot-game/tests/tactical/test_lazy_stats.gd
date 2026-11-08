extends SceneTree

const Soldiers = preload("res://scripts/tactical/regiment_soldiers.gd")
const Physics = preload("res://scripts/tactical/soldier_physics.gd")


class NavigationStub:
	extends RefCounted

	static func navigator(_r, _kind: String, _u: Dictionary = {}) -> String:
		return "test"


class ClearTerrain:
	extends RefCounted

	func clear_segment(_nav: String, _from: Vector2, _to: Vector2) -> bool:
		return true


class RulesProbe:
	extends RefCounted

	var data: Dictionary = {}
	var config_reads: int = 0
	var Soldiers
	var terrain

	var config: Dictionary:
		get:
			config_reads += 1
			return data


var failures: int = 0
var checks: int = 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func type_stats(radius: float, speed: float, interval: float) -> Dictionary:
	return {
		"individual": {"unit_size": radius, "range": 25.0},
		"speed": speed,
		"interval": interval,
	}


# Deliberately retain the original eager expression as the test oracle.
func old_individual(r, u: Dictionary) -> Dictionary:
	return u.get(
		"individual_stats",
		r.config.types.get(u.kind, {}).get("individual", {})
	)


func verify_individual(r, u: Dictionary, label: String) -> void:
	var expected: Dictionary = old_individual(r, u)
	var unit_before: PackedByteArray = var_to_bytes(u)
	var config_before: PackedByteArray = var_to_bytes(r.data)

	r.config_reads = 0
	var actual: Dictionary = Soldiers.individual(r, u)

	check(
		r.config_reads == (0 if u.has("individual_stats") else 1),
		label + ": individual config reads"
	)
	check(
		var_to_bytes(actual) == var_to_bytes(expected),
		label + ": individual value"
	)

	# A stored dictionary must be returned by reference, including an empty one.
	# Missing fallbacks instead construct a fresh empty dictionary.
	var stored_dictionary: bool = (
		u.has("individual_stats")
		or r.data.types.get(u.kind, {}).has("individual")
	)
	if stored_dictionary:
		check(is_same(actual, expected), label + ": individual identity")

	check(var_to_bytes(u) == unit_before, label + ": accessor wrote unit")
	check(var_to_bytes(r.data) == config_before, label + ": accessor wrote config")


func verify_valid_type(r, u: Dictionary, label: String) -> void:
	verify_individual(r, u, label)

	# Original combat expression: valid type required, even with an override.
	var expected: Dictionary = u.get("combat_stats", r.config.types[u.kind])
	var expected_interval: float = expected.interval
	var expected_speed: float = expected.speed
	var expected_reads: int = 0 if u.has("combat_stats") else 1
	var actor: Dictionary = u.soldiers[0]

	actor.attack_engaged = Vector2i(99, 0)
	r.config_reads = 0
	Soldiers.start_mounted_shot(r, u, actor, {}, {})

	check(r.config_reads == expected_reads, label + ": shot config reads")
	check(
		var_to_bytes(actor.cooldown) == var_to_bytes(expected_interval),
		label + ": shot interval"
	)
	check(actor.attack_age == 0.0, label + ": actor attack age")
	check(u.attack_age == 0.0, label + ": unit attack age")
	check(actor.attack_pending, label + ": pending shot")
	check(not actor.has("attack_engaged"), label + ": mounted engagement")

	actor.position = Vector2.ZERO
	actor.velocity = Vector2(1000.0, 0.0)
	var row: Dictionary = {"unit": u, "slot": 0}
	var expected_velocity: Vector2 = Vector2(1000.0, 0.0).limit_length(
		expected_speed + 60.0
	)

	r.config_reads = 0
	Physics.integrate(r, [row], 1.0 / 60.0)

	check(r.config_reads == expected_reads, label + ": integration config reads")
	check(
		var_to_bytes(actor.velocity) == var_to_bytes(expected_velocity),
		label + ": integration speed cap"
	)


func _initialize() -> void:
	var r = RulesProbe.new()
	r.Soldiers = NavigationStub
	r.terrain = ClearTerrain.new()
	r.data = {
		"types": {
			"spear": type_stats(9.0, 90.0, 1.25),
			"archer": type_stats(8.0, 100.0, 0.75),
		}
	}

	var u: Dictionary = {
		"kind": "spear",
		"stun": 0.0,
		"petrified": 0.0,
		"individual_stats": {"unit_size": 13.0, "range": 30.0},
		"combat_stats": {"speed": 120.0, "interval": 0.4},
		"soldiers": [{
			"position": Vector2.ZERO,
			"velocity": Vector2.ZERO,
			"death_state": 0,
			"attack_age": 10.0,
			"cooldown": 0.0,
		}],
	}
	verify_valid_type(r, u, "initial overrides")

	u.individual_stats.unit_size = 17.0
	u.combat_stats.speed = 140.0
	u.combat_stats.interval = 0.6
	verify_valid_type(r, u, "mutated overrides")

	u.individual_stats = {"unit_size": 21.0, "range": 35.0}
	u.combat_stats = {"speed": 160.0, "interval": 0.8}
	verify_valid_type(r, u, "replaced overrides")

	u.individual_stats = {}
	verify_valid_type(r, u, "empty individual override wins")

	u.erase("individual_stats")
	u.erase("combat_stats")
	verify_valid_type(r, u, "removed overrides")

	r.data.types.spear.individual.unit_size = 23.0
	r.data.types.spear.speed = 180.0
	r.data.types.spear.interval = 1.5
	verify_valid_type(r, u, "mutated configuration")

	r.data.types.spear.individual = {"unit_size": 27.0, "range": 40.0}
	verify_valid_type(r, u, "replaced nested individual")

	r.data.types.spear = type_stats(29.0, 200.0, 1.75)
	verify_valid_type(r, u, "replaced type")

	u.kind = "archer"
	verify_valid_type(r, u, "changed kind")

	r.data.types = {"archer": type_stats(31.0, 220.0, 2.0)}
	verify_valid_type(r, u, "replaced types table")

	r.data = {"types": {"archer": type_stats(33.0, 240.0, 2.25)}}
	verify_valid_type(r, u, "replaced entire config")

	r.data.types.archer.erase("individual")
	verify_valid_type(r, u, "missing configured individual")

	var empty_individual: Dictionary = Soldiers.individual(r, u)
	empty_individual["must_not_persist"] = true
	verify_valid_type(r, u, "fresh missing-individual fallback")
	check(not u.has("individual_stats"), "fallback must not populate unit")

	# Combat fallback is intentionally strict, so only test individual here.
	u.kind = "unknown"
	verify_individual(r, u, "unknown kind")

	var empty_type: Dictionary = Soldiers.individual(r, u)
	empty_type["must_not_persist"] = true
	verify_individual(r, u, "fresh unknown-kind fallback")

	u.individual_stats = {}
	verify_individual(r, u, "empty override with unknown kind")

	u.individual_stats = {"unit_size": 37.0}
	verify_individual(r, u, "override with unknown kind")

	if failures == 0:
		print("Lazy stats: ", checks, " checks, ", failures, " failures")
		quit(0)
	else:
		push_error("%d regression checks failed" % failures)
		quit(1)

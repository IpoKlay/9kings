extends SceneTree

const Rules = preload("res://scripts/tactical/trial_rules.gd")
var failures := 0

func check(ok: bool, note: String):
	if not ok:
		push_error(note)
		failures += 1

func fixture(kind: String, opponent: String):
	var r = Rules.new(false)
	r.units.clear()
	r.spawn(kind, "ally", Vector2(600, 600))
	r.spawn(opponent, "enemy", Vector2(650, 600))
	r.units[1].stun = 10
	r.start()
	return r

func _initialize():
	var roster = Rules.new()
	check(roster.deploy_combined(), "Seven-arms deployment")
	check(not roster.deploy_combined(), "Cannot duplicate a deployed army")
	for side in ['ally','enemy']:
		var kinds = roster.alive(side).map(func(unit):return unit.kind)
		for kind in roster.config.types:
			check(kinds.count(kind)==1, "One formation per arm and side")
			var texture=load("res://assets/rts-armies/%s_%s.png" % [kind,side]) as Texture2D
			check(texture!=null and texture.get_size()==Vector2(1088,512),"Full directional art for "+kind)
	var r=fixture("medic","archer")
	r.units[0].hp-=1
	var hp: float=r.units[1].hp
	r.step(.016)
	check(r.units[0].hp==r.units[0].max_hp and r.units[1].hp==hp,"Healing caps at max and does no enemy damage")
	var siege=fixture("siege","legion")
	siege.spawn("archer","enemy",Vector2(665,608))
	siege.units[2].stun=10
	siege.step(.016)
	check(siege.stones.size()==1 and siege.units[1].hp==siege.units[1].max_hp,"Stone has a flight time")
	siege.advance_stones(1)
	check(siege.units[1].hp<siege.units[1].max_hp and siege.units[2].hp<siege.units[2].max_hp and siege.units[0].hp==siege.units[0].max_hp,"Direct and splash hits affect enemies only")
	for pair in [["spear","cavalry"],["archer","guard"]]:
		r=fixture(pair[0],pair[1])
		r.step(.016)
		var damage: float=r.config.types[pair[0]].damage
		var expected:=damage*1.5 if pair[0]=="spear" else damage*.45
		check(is_equal_approx(r.units[1].max_hp-r.units[1].hp,expected),"Matchup "+str(pair))
	r=fixture("legion","archer")
	r.units[0].hp=0
	r.reserve={"medic":1}
	r.step(.016)
	check(r.phase=="battle","Auxiliary reserve can still deploy")
	r.reserve.medic=0
	r.step(.016)
	check(r.phase=="defeat","No remaining reserves")
	print("Seven-arm integration: ",failures," failures")
	quit(1 if failures else 0)

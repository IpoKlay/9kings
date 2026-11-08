extends SceneTree
const Rules=preload("res://scripts/tactical/trial_rules.gd")
const PassRules=preload("res://scripts/tactical/pass_battle.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;printerr(label)
func _initialize():call_deferred('run')
func run():
	for pass_rules in [false,true]:
		var r=PassRules.new() if pass_rules else Rules.new()
		r.units.clear()
		for side in ['ally','enemy']:
			for hp in [-1.,0.,1e-20,100.]:
				for routing in [false,true]:
					r.units.append({'hp':hp,'side':side,'routing':routing,'escaped':true,'death_state':2})
		var shared: Dictionary=r.units[4]
		r.units.append(shared)
		for side in ['ally','enemy','missing']:
			var oracle=r.units.filter(func(u):return u.side==side and u.hp>0 and not u.routing) if pass_rules else r.units.filter(func(u):return u.hp>0 and u.side==side)
			var actual=r.alive(side)
			check(actual.size()==oracle.size(),'length')
			for i in mini(actual.size(),oracle.size()):check(is_same(actual[i],oracle[i]),'ordered dictionary identity')
			actual.clear();check(r.units.size()==17,'independent output array')
		var held=r.alive('ally')
		held[0].marker=42;check(shared.marker==42,'live dictionary reference')
		shared.hp=0.
		check(is_same(held[0],shared) and held[0].hp==0.,'retained membership/live HP')
		check(not r.alive('ally').has(shared),'fresh death filter')
		shared.hp=1e-20
		check(is_same(r.alive('ally')[0],shared),'reinclusion in source order')
		shared.side='enemy'
		check(held[0].side=='enemy' and not r.alive('ally').has(shared),'fresh side/retained reference')
		shared.side='ally';shared.routing=true
		check(r.alive('ally').has(shared)==not pass_rules,'override routing contract')
		r.units.clear();check(r.alive('ally').is_empty(),'empty source')
	print('Alive contract: %d checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)

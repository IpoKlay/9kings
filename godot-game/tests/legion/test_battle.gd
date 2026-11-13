extends SceneTree
const Battle = preload('res://scripts/legion/battle.gd')
const Formation = preload('res://scripts/legion/formations.gd')
var checks = 0
var failures = 0

func check(value: bool, message: String):
	checks += 1
	if not value: failures += 1; printerr('FAIL: '+message)

func step(b, seconds: float):
	for i in roundi(seconds*30): b.update(1.0/30.0)

func _initialize():
	call_deferred('run')

func run():
	var b = Battle.new()
	check(b.phase == 'deploy' and b.strength('ally') == 140 and b.strength('enemy') == 120,'four full allied regiments and configured enemy army')
	for r in b.regiments:
		check(b.members(r).size() == (35 if r.side == 'ally' else 30),'correct regiment size')
		for id in r.members:
			check(b.legal_point(b.soldiers[id].pos),'spawn outside obstacles and within battlefield')
	var frozen = b.soldiers.duplicate(true)
	step(b,3)
	check(b.soldiers == frozen and b.elapsed == 0,'deployment freezes both armies')
	check(not b.deploy([0],Vector2(1000,500)),'deployment rejects enemy half')
	check(b.regiments[0].pos == Vector2(800,1140),'invalid deployment is atomic')
	check(b.deploy([0],Vector2(650,1200),Vector2.RIGHT),'reposition and rotate entire legion')
	check(b.regiments[0].heading == Vector2.RIGHT and b.soldiers[0].pos != frozen[0].pos,'rotation changes real soldier slots')
	check(not b.set_formation([3],'testudo'),'archers cannot use testudo')
	check(b.set_formation([0],'ring'),'ring can be deployed with enough space')
	check(b.deploy([3],Vector2(650,1200)),'another regiment can occupy empty ring center')
	check(not b.deploy([1],Vector2(650,1200)),'overlapping actual soldiers is rejected')
	check(is_equal_approx(Battle.damage_value(10,[0.1],[0.2],5,[0.2]),2.8),'reference damage example equals 2.8')
	check(is_equal_approx(Battle.damage_value(10,[0.2,0.3],[],0,[]),15.0),'bonuses add rather than multiply')
	check(Battle.damage_value(5,[],[],20,[]) == 0,'armor never heals the target')
	b = Battle.new()
	check(b.start() and not b.start(),'only one deployment-to-battle transition')
	check(b.set_formation([0],'wedge'),'battle formation order accepted')
	check(not b.set_formation([0],'ring'),'cannot replace unfinished formation')
	step(b,2.9)
	check(b.regiments[0].form == 'default','formation does not finish early')
	step(b,0.2)
	check(b.regiments[0].form == 'wedge' and b.regiments[0].form_cd > 9,'three-second formation then ten-second cooldown')
	check(not b.set_formation([0],'default'),'cooldown enforced')
	# Melee contact fixture: only the changing legion is prevented from attacking.
	b = Battle.new(); b.start()
	for r in b.regiments: r.order = 'hold'
	var attacker = b.soldiers[0]; var defender = b.soldiers[140]
	attacker.pos = Vector2(1100,800); defender.pos = Vector2(1130,800)
	attacker.target = defender.id; attacker.cooldown = 0
	check(b.set_formation([0],'wedge'),'contact reform accepted')
	step(b,0.1)
	check(defender.hp == defender.max_hp,'changing formation blocks actual attacks')
	b = Battle.new(); b.start()
	var archer = b.regiments[3]
	check(not b.arrow_rain([3],Vector2(400,400)),'arrow rain range is enforced')
	var target = b.soldiers[140]
	target.pos = archer.pos+Vector2(0,-250)
	b.regiments[target.regiment].order = 'hold'
	check(b.arrow_rain([3],target.pos),'arrow rain creates a delayed area attack')
	check(not b.arrow_rain([3],target.pos),'arrow rain cooldown enforced')
	var before: float = target.hp
	step(b,1.4)
	check(target.hp < before,'arrow rain causes actual independent damage')
	# Safe rear recovery heals survivors, never dead members.
	b = Battle.new(); b.start()
	for r in b.regiments: r.order = 'hold'
	var wounded = b.soldiers[0]; wounded.hp = 20
	b.hit(b.soldiers[1],999,false)
	check(b.command([0],'retreat'),'retreat order accepted')
	step(b,9)
	check(wounded.hp > 20 and b.soldiers[1].hp == 0,'retreat heals only living soldiers')
	check(b.strength('ally') == 139,'individual death reduces army by exactly one')
	# Natural complete battle, no forced winning state or timeout.
	b = Battle.new(); b.start()
	var start_us = Time.get_ticks_usec()
	step(b,160)
	var wall_ms = (Time.get_ticks_usec()-start_us)/1000.0
	check(b.phase in ['victory','defeat'],'ordinary battle reaches a natural result')
	check(b.losses.ally + b.strength('ally') == 140 and b.losses.enemy + b.strength('enemy') == 120,'loss accounting remains exact')
	check(b.soldiers.all(func(s): return s.hp == 0 or s.hp == s.max_hp),'survivors restore HP at battle end')
	print('NATURAL RESULT: ',b.phase,' time=',b.elapsed,' allies=',b.strength('ally'),' enemies=',b.strength('enemy'),' wall_ms=',wall_ms)
	# Defeat path with explicit fixture, separate from natural match above.
	b = Battle.new(); b.start()
	for s in b.alive('ally'): b.hit(s,9999,false)
	b.update(1.0/30.0)
	check(b.phase == 'defeat','all allied regiments lost produces defeat')
	print('LEGION CHECKS=',checks,' FAILURES=',failures)
	quit(1 if failures else 0)

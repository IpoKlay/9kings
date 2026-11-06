extends SceneTree
const Rules=preload('res://scripts/tactical/trial_rules.gd')
var checks=0
var failures=0
func _initialize():call_deferred('run')
func fixture():
	var r=Rules.new()
	r.units.clear()
	r.spawn('legion','ally',Vector2(650,500))
	r.spawn('legion','enemy',Vector2(1000,500))
	r.spawn('archer','enemy',Vector2(1150,500))
	r.phase='battle'
	r.elapsed=60
	return r
func tick(r, seconds: float, dt: float=1.0/60):
	var remaining=seconds
	while remaining>.000001:
		var step=minf(dt,remaining)
		r.powers.advance(r,step)
		remaining-=step
func cast(r, id: String, pos=Vector2(1000,500)):
	assert(r.select_deity(id))
	assert(r.strike(pos))
func check(value: bool):
	if not value:
		failures+=1
		push_error('MYTH CHECK FAILED '+str(checks)+' '+str(get_stack()))
	checks+=1
func run():
	create_timer(20).timeout.connect(func():push_error('MYTH TEST TIMEOUT');quit(1))
	var r=fixture()
	cast(r,'athena',Vector2(650,500))
	check(r.units[0].shield==0)
	tick(r,.35)
	check(r.units[0].shield>0 and r.units[1].shield==0)
	check(is_equal_approx(r.hurt(r.units[0],100),35))
	cast(r,'athena',Vector2(650,500));tick(r,.35)
	check(is_equal_approx(r.hurt(r.units[0],100),35))
	tick(r,6.1)
	check(is_equal_approx(r.hurt(r.units[0],100),100))
	print('ATHENA protection, no stacking, expiration PASS')

	r=fixture()
	r.spawn('archer','ally',Vector2(700,500))
	r.spawn('cavalry','enemy',Vector2(780,550))
	cast(r,'artemis',Vector2(1100,500));tick(r,.35)
	check(r.units[1].marked>0 and r.units[2].marked==0)
	check(r.powers.select_target(r,r.units[3]).id==r.units[1].id)
	var hp: float=r.units[1].hp
	r.step(1.0/60)
	check(is_equal_approx(hp-r.units[1].hp,12*1.4*.65))
	cast(r,'artemis',Vector2(1150,500));tick(r,.35)
	check(r.units.filter(func(u):return u.marked>0).size()==1)
	tick(r,8.1);check(r.units.all(func(u):return u.marked==0))
	print('ARTEMIS strongest target, real archer focus/bonus, replacement PASS')

	r=fixture()
	cast(r,'hephaestus');tick(r,.5)
	check(is_equal_approx(r.units[1].hp,925-70))
	check(is_equal_approx(r.powers.speed_multiplier(r.units[1]),.55))
	check(r.powers.speed_multiplier(r.units[0])==1)
	tick(r,2)
	check(is_equal_approx(r.units[1].hp,925-70-110))
	cast(r,'hephaestus',Vector2(1500,500));tick(r,.5)
	hp=r.units[1].hp;tick(r,1)
	check(is_equal_approx(hp,r.units[1].hp) and r.powers.zones.size()==1)
	tick(r,5);check(r.powers.zones.is_empty())
	print('HEPHAESTUS eruption, exact DPS, slow, relocation, expiration PASS')

	r=fixture()
	cast(r,'demeter');tick(r,.6)
	check(r.units[1].rooted>0 and r.units[0].rooted==0)
	var pos: Vector2=r.units[1].pos
	r.step(.1);check(r.units[1].pos==pos)
	r.units[1].pos=Vector2(700,500)
	hp=r.units[0].hp;r.step(.1)
	check(r.units[0].hp<hp)
	tick(r,3.1);check(r.units[1].rooted==0)
	print('DEMETER stops movement, still attacks, expires PASS')

	for id in ['achilles','minotaur']:
		r=fixture()
		r.spawn('legion','enemy',Vector2(850,500))
		r.spawn('legion','ally',Vector2(1000,520))
		cast(r,id)
		check(r.powers.charges.is_empty())
		tick(r,1.2)
		var damage: float=r.powers.config[id].damage
		for u in r.alive('enemy'):check(is_equal_approx(u.max_hp-u.hp,damage) and u.push.x>0)
		hp=r.units[1].hp;tick(r,1)
		check(hp==r.units[1].hp and r.powers.charges.is_empty())
		check(r.units[4].hp==r.units[4].max_hp)
		print(id.to_upper(),' travelling hits once, knockback, ally safety PASS')

	r=fixture()
	cast(r,'odysseus',Vector2(930,500));tick(r,.4)
	check(r.powers.decoys.size()==3)
	check(r.powers.select_target(r,r.units[1]).kind=='decoy')
	for i in 120:r.step(1.0/60)
	var decoy_hp=0.0
	for d in r.powers.decoys:decoy_hp+=d.hp
	check(decoy_hp<300)
	check(r.units.size()==3)
	tick(r,6.1);check(r.powers.decoys.is_empty())
	check(r.powers.select_target(r,r.units[1]).kind=='legion')
	print('ODYSSEUS real aggro, damageable decoys, expiry without permanent units PASS')

	for id in ['heracles','cyclops','harpy']:
		r=fixture()
		r.spawn('legion','ally',Vector2(1010,520))
		cast(r,id)
		tick(r,float(r.powers.config[id].windup)-.02)
		check(r.units[1].hp==r.units[1].max_hp)
		tick(r,.05)
		check(is_equal_approx(r.units[1].hp,925-r.powers.config[id].damage))
		check(r.units[1].stun>0 and r.units[1].push.length()>0)
		check(r.units[3].hp==925)
		if id=='harpy':check(r.units[2].hp==r.units[2].max_hp)
		print(id.to_upper(),' timed AoE damage, stun, push and ally safety PASS')

	r=fixture()
	r.units[1].pos=Vector2(700,500)
	r.units[2].pos=Vector2(700,800)
	r.units[2].cooldown=1000
	cast(r,'medusa',Vector2(700,500));tick(r,.5)
	check(r.units[1].petrified>0 and r.units[0].petrified==0 and r.units[2].petrified==0)
	pos=r.units[1].pos;hp=r.units[0].hp
	r.units[1].push=Vector2(120,0)
	for i in 60:r.step(1.0/60)
	check(r.units[1].pos==pos and r.units[0].hp==hp and r.units[1].push==Vector2.ZERO)
	tick(r,4.1);r.step(.1)
	check(r.units[0].hp<hp and r.units[1].petrified==0)
	print('MEDUSA cone boundaries, no movement or attack, automatic recovery PASS')

	var totals=[]
	for dt in [1.0/30,1.0/60,1.0/120]:
		r=fixture()
		r.units[0].hp=500
		r.spawn('legion','enemy',Vector2(1010,530))
		r.spawn('legion','enemy',Vector2(1030,500))
		cast(r,'hydra');tick(r,.5,dt)
		check(r.units.filter(func(u):return u.poison>0).size()==3)
		check(r.units[0].regen>0 and r.units[0].poison==0)
		tick(r,5.1,dt)
		check(is_equal_approx(r.units[1].hp,925-65-175))
		check(is_equal_approx(r.units[0].hp,620))
		check(r.units[1].poison==0 and r.units[0].regen==0)
		totals.append(r.units[1].hp)
	check(is_equal_approx(totals[0],totals[2]))
	r=fixture();r.units[0].hp=0
	cast(r,'hydra');tick(r,6)
	check(r.units[0].hp==0 and r.units[0].regen==0)
	print('HYDRA 3 heads, exact poison/regen at 30/60/120Hz, no resurrection PASS')

	r=fixture();r.units[0].hp=900
	cast(r,'hydra');tick(r,6)
	check(r.units[0].hp==r.units[0].max_hp)
	r=fixture();cast(r,'hydra');tick(r,1)
	cast(r,'hydra');tick(r,.5)
	hp=r.units[1].hp;tick(r,1)
	check(is_equal_approx(hp-r.units[1].hp,35))
	r.units[1].hp=1;tick(r,1)
	check(r.units[1].hp==0)
	r=fixture();cast(r,'odysseus');tick(r,.4)
	r.units[0].hp=0;r.reserve={'legion':0,'archer':0,'cavalry':0}
	r.step(.1)
	check(r.phase=='defeat' and r.powers.decoys.is_empty())
	print('RECAST AND DEATH: poison refresh, healing cap, no negative HP, decoys cannot prevent defeat PASS')

	for row in r.characters:
		r=fixture()
		cast(r,row.id)
		check(not r.strike(Vector2(-1,-1)))
		for i in 30:check(r.strike(Vector2(1000,500)))
		check(r.charges==2 and r.cooldown==0)
		r.elapsed=179.99;r.step(.02)
		check(r.phase in ['victory','timeout','defeat'] and r.powers.pending.is_empty() and r.powers.charges.is_empty() and r.powers.zones.is_empty() and r.powers.decoys.is_empty())
		check(not r.strike(Vector2(1000,500)))
		var limited=Rules.new(false)
		check(limited.select_deity(row.id))
		limited.deploy('legion',Vector2(650,420));limited.start()
		check(limited.strike(Vector2(1000,500)) and not limited.strike(Vector2(1000,500)))
	print('ALL 14: unlimited casts, bounds, limited rules, terminal cleanup PASS')
	print('MYTH SKILLS: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)

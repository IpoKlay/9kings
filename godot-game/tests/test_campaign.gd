extends SceneTree
const Campaign = preload('res://scripts/campaign.gd')
var checks = 0
var failures = 0
func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr('FAIL: '+label)
func fight(c):
	c.g.phase='prepare'
	c.start()
	# Legacy fixtures cover combat after the new camp departure, not its added duration.
	c.g.battle.deploy_elapsed=c.combat.deployment_seconds
	for u in c.g.battle.units:
		if u.side=='ally':u.x=u.deployTo.x;u.y=u.deployTo.y
	while c.g.phase=='battle': c.step(1.0/60)
	return c.g.battle.report
func _init():
	# Historical formations are varied combat fixtures; their old timing depended on
	# automatic role sorting and is intentionally obsolete with positional deployment.
	var fixtures=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/combat_reference.json'))
	for f in fixtures:
		var c=Campaign.new(1);var same=Campaign.new(1)
		c.g.merge(f.initial.duplicate(true),true)
		c.g.unlocked_cells=range(25)
		same.g=c.g.duplicate(true)
		var result=fight(c);var repeated=fight(same)
		check(result==repeated and is_equal_approx(c.g.battle.time,same.g.battle.time),'Combat resolves deterministically for historical roster '+str(c.g.round))
		check(result.enemyCount==c.current_encounter().roster.size() and result.enemyLosses<=result.enemyCount,'Report counts only deployed enemies')
		check(result.deployed==c.g.buildings.filter(func(b):return c.types[b.type].has('role')).size(),'Every playable occupant is deployed')
		check(result.won or result.defenseLost>=1,'Combat resolves with victory or life loss')
	var draws=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/draw_reference.json'))
	for f in draws:
		var c=Campaign.new(int(f.seed))
		var same=Campaign.new(int(f.seed))
		for i in f.years.size():
			c.g.round=i+1;same.g.round=i+1
			var hand=c.offers()
			check(hand==same.offers() and hand.size()==3 and hand.all(func(id):return c.available(id)), 'Deterministic eligible draws seed %s year %s'%[f.seed,i+1])
	var c=Campaign.new(42)
	var offered=c.offers()
	check(c.offers()==offered,'Draw stable within year')
	check(not c.choose('not-a-card'),'Reject invalid selection')
	c.g.phase='reward'
	c.g.offered=['legion','shield','testudo']
	check(c.choose('legion'),'Choose construction')
	c.g.buildings.append({'id':2,'type':'archer','cell':11,'level':1})
	check(not c.place(11),'Reject wrong camp upgrade')
	check(not c.place(-1) and not c.place(25),'Reject invalid cell')
	check(c.place(12) and c.g.buildings[0].level==2,'Upgrade matching camp')
	check(not c.place(1),'Only one reward per year')
	for year in 3:
		c.g.phase='prepare'
		c.start()
		c.finish(false)
		check(c.g.defense==2-year,'Lose exactly one life')
		if year<2: check(c.next_year(),'Advance after surviving loss')
	check(c.g.phase=='defeat' and not c.next_year(),'Three losses end campaign')
	c=Campaign.new(5)
	c.g.phase='prepare'
	c.g.armyTestudo=true
	var units=c.muster()
	check(units.filter(func(u):return u.get('testudo',false)).size()==1,'Testudo only legionaries')
	c.g.orders={'volley':true}
	c.g.armyShield=true
	c.start()
	c.finish(true)
	c.next_year()
	check(not c.g.armyShield and not c.g.armyTestudo and c.g.orders.is_empty(),'Temporary orders expire')
	c=Campaign.new(3)
	c.g.buildings=[]
	for i in c.g.unlocked_cells: c.g.buildings.append({'id':i+1,'type':'legion','cell':i,'level':3})
	for id in c.cards:
		if c.cards[id].has('max'): c.g.upgrades[id]=c.cards[id].max
	for i in 10:
		c.g.round=i+1
		var hand=c.offers()
		check(hand.size()==3 and hand.all(func(id):return c.cards[id].kind=='Battle order'),'Full camp still draws three usable orders')
	print('%s checks, %s failures' % [checks,failures])
	quit(1 if failures else 0)

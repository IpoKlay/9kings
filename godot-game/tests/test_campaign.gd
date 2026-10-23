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
	while c.g.phase=='battle': c.step(1.0/60)
	return c.g.battle.report
func _init():
	var fixtures=JSON.parse_string(FileAccess.get_file_as_string('res://data/combat_reference.json'))
	for f in fixtures:
		var c=Campaign.new(1)
		c.g=f.initial.duplicate(true)
		var result=fight(c)
		check(result.keys().all(func(k):return result[k]==f.report[k]),'JS combat parity year %s / upgraded %s: %s vs %s' % [c.g.round,not c.g.upgrades.is_empty(),result,f.report])
		check(abs(c.g.battle.time-f.time)<.05,'Combat duration year %s'%c.g.round)
	var draws=JSON.parse_string(FileAccess.get_file_as_string('res://data/draw_reference.json'))
	for f in draws:
		var c=Campaign.new(int(f.seed))
		for i in f.years.size():
			c.g.round=i+1
			check(c.offers()==f.years[i],'JS draw parity seed %s year %s'%[f.seed,i+1])
	var c=Campaign.new(42)
	var offered=c.offers()
	check(c.offers()==offered,'Draw stable within year')
	check(not c.choose('not-a-card'),'Reject invalid selection')
	c.g.offered=['legion','shield','testudo']
	check(c.choose('legion'),'Choose construction')
	check(not c.place(2),'Reject wrong camp upgrade')
	check(not c.place(-1) and not c.place(12),'Reject invalid cell')
	check(c.place(0) and c.g.buildings[0].level==2,'Upgrade matching camp')
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
	for i in 12: c.g.buildings.append({'id':i+1,'type':'legion','cell':i,'level':3})
	for id in c.cards:
		if c.cards[id].has('max'): c.g.upgrades[id]=c.cards[id].max
	for i in 10:
		c.g.round=i+1
		var hand=c.offers()
		check(hand.size()==3 and hand.all(func(id):return c.cards[id].kind=='Battle order'),'Full camp still draws three usable orders')
	print('%s checks, %s failures' % [checks,failures])
	quit(1 if failures else 0)

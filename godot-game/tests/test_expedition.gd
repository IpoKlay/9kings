extends SceneTree
const Campaign = preload('res://scripts/campaign.gd')
const Expedition = preload('res://scripts/expedition.gd')
var checks = 0
var failures = 0
func check(value: bool,message: String):
	checks += 1
	if not value:
		failures += 1
		printerr('FAIL: '+message)
func supply(c,e):
	var choices = c.offers()
	var picked = choices[0]
	for id in ['guard','legion','archer','siege','spear','medic','cavalry','shieldDrill','combinedArms','fireArrows']:
		if id in choices:
			picked=id
			break
	check(c.choose(picked),'Reward accepted')
	if c.g.phase == 'place':
		var cell = -1
		for b in c.g.buildings:
			if b.type==picked and b.level<3: cell=int(b.cell); break
		if cell<0:
			for i in 12:
				if c.building_at(i)==null: cell=i; break
		check(c.place(cell),'Building placed')
	check(e.finish_supply(),'Supply returns to map')
func fight(c):
	var ticks = 0
	while c.g.phase=='battle' and ticks<4800:
		c.step(1.0/60)
		ticks+=1
	check(c.g.battle.report!=null,'Combat resolves')
	return c.g.battle.report.won
func _init():
	var c=Campaign.new(23)
	var e=Expedition.new(c)
	check(c.g.phase=='reward' and e.state.mode=='camp','Existing initial card hand retained')
	check(not e.can_travel('148127'),'Must finish initial reward')
	supply(c,e)
	check(e.known('246349') and not e.known('727070'),'Only next two stops reveal intel')
	check(not e.travel('727070'),'Cannot jump to final city')
	for id in ['148127','246349','256177','314921','462503','373778','442509','579885','658381','727070']:
		var before_build=c.g.buildings.duplicate(true)
		var before_upgrades=c.g.upgrades.duplicate(true)
		check(e.travel(id),'Reach '+id)
		check(not e.travel(id),'Cannot replay a node or start twice')
		if c.g.phase=='battle':
			var predicted=e.encounter(id)
			var enemy_units=c.g.battle.units.filter(func(u):return u.side=='enemy')
			check(enemy_units.size()==predicted.roster.size(),'Intel equals actual enemy count')
			for u in enemy_units: check(is_equal_approx(u.hp,c.enemies[u.type].hp*predicted.health),'Intel equals actual enemy HP')
			check(fight(c),'Campaign victory at '+id)
			check(e.settle(),'One settlement')
			check(not e.settle(),'No duplicate settlement')
		check(c.g.buildings==before_build and c.g.upgrades==before_upgrades,'Army and permanent growth preserved between scenes')
		check(e.state.current==id,'Map advances on success')
		if id=='246349': check(not e.can_travel('265849'),'Chosen route closes sibling branch')
		if c.g.phase=='reward': supply(c,e)
	check(e.state.finished and e.state.mode=='map','Whole Mediterranean completed in one run')
	check(not e.can_travel('727070'),'Final city cannot be farmed')
	c=Campaign.new(5)
	e=Expedition.new(c)
	c.skip(); e.finish_supply()
	c.g.defense=2
	c.g.orders={'shield':true}; c.g.armyShield=true
	e.travel('148127')
	check(c.g.defense==3,'Friendly port restores one life')
	check(c.g.armyShield and c.g.orders.has('shield'),'Peaceful port does not consume battle orders')
	c.skip();e.finish_supply()
	for loss in 3:
		check(e.travel('246349'),'Retry the same target')
		for u in c.g.battle.units:
			if u.side=='ally': u.hp=0
		c.step(.1)
		check(c.g.defense==2-loss,'Failure costs exactly one life')
		check(e.state.current=='148127','Failure cannot advance map')
		if loss<2:
			check(e.settle(),'Defeat returns to map')
			check(c.g.phase=='prepare' and not e.state.reward_due,'No victory reward on defeat')
			check(not e.can_travel('265849'),'Committed branch stays locked')
			check(c.g.orders.is_empty() and not c.g.armyShield,'Combat consumes orders')
		else: check(c.g.phase=='defeat' and not e.settle(),'Third loss ends campaign')
	print('%d expedition checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)

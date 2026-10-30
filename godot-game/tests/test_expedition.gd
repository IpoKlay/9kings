extends SceneTree
const Campaign = preload('res://scripts/campaign.gd')
const Expedition = preload('res://scripts/expedition.gd')
var checks = 0
var failures = 0
var actual_wins=0
var settlement_fixtures=0
func check(value: bool,message: String):
	checks += 1
	if not value:
		failures += 1
		printerr('FAIL: '+message)
func supply(c,e):
	while c.g.expansion_credits>0 and not c.expansion_candidates().is_empty():
		check(c.expand(c.expansion_candidates()[0]),'Use independently awarded expansion')
	var choices = c.offers()
	var picked = choices[0]
	for id in ['guard','legion','archer','siege','spear','medic','cavalry','shieldDrill','combinedArms','fireArrows']:
		if id in choices:
			picked=id
			break
	check(c.choose(picked),'Reward accepted')
	if c.g.phase == 'place':
		var cell = -1
		# Recruit into free plots first; higher population matters with the bare start.
		if c.g.buildings.size()<8:
			for i in c.g.unlocked_cells:
				if c.building_at(i)==null: cell=i; break
		if cell<0:
			for b in c.g.buildings:
				if b.type==picked and b.level<3: cell=int(b.cell); break
		if cell<0:
			for i in c.g.unlocked_cells:
				if c.building_at(i)==null: cell=i; break
		check(c.place(cell),'Building placed')
	# Test-player strategy: deliberately arrange front troops ahead of ranged units.
	# Production muster preserves positions and never performs this sorting.
	var plots=c.g.unlocked_cells.duplicate()
	plots.sort_custom(func(a,b):return a%5>b%5 if a%5!=b%5 else abs(a/5-2)<abs(b/5-2))
	var army=c.g.buildings.duplicate()
	army.sort_custom(func(a,b):return (0 if c.types[a.type].get('role','rear')=='front' else 1)<(0 if c.types[b.type].get('role','rear')=='front' else 1))
	for i in army.size():c.relocate(army[i].id,plots[i])
	check(e.finish_supply(),'Supply returns to map')
func fight(c):
	var ticks = 0
	while c.g.phase=='battle' and ticks<4800*c.g.battle.get('waves',[{}]).size():
		c.step(1.0/60)
		ticks+=1
	check(c.g.battle.report!=null,'Combat resolves')
	if c.g.battle.report==null: return false
	print('CITY ',c.g.expedition_wave.name,' waves=',c.g.battle.get('waves',[]).size(),' seconds=',snapped(c.g.battle.time,.1),' won=',c.g.battle.report.won,' cleared=',c.g.battle.get('waves_cleared',0))
	return c.g.battle.report.won
func _init():
	var args = OS.get_cmdline_user_args()
	var seed_value = int(args[0]) if args.size()>0 else 23
	var branch = int(args[1]) if args.size()>1 else 0
	var c=Campaign.new(seed_value)
	var e=Expedition.new(c)
	check(c.g.phase=='prepare' and e.state.mode=='map','Run begins at destination selection')
	check(not e.can_travel('148127') and e.can_travel('246349'),'Departure port folds into the first destination')
	check(e.known('246349') and not e.known('727070'),'Only next two stops reveal intel')
	check(not e.travel('727070'),'Cannot jump to final city')
	var route: Array = []
	var cursor = e.data.start
	while not e.next(cursor).is_empty():
		cursor = e.next(cursor)[mini(branch,e.next(cursor).size()-1)]
		route.append(cursor)
	check(route.size()==45,'A complete itinerary has 45 stops')
	for id in route.slice(1):
		check(e.travel(id),'Reach '+id)
		if e.state.opening=='card': supply(c,e)
		var before_build=c.g.buildings.duplicate(true)
		var before_upgrades=c.g.upgrades.duplicate(true)
		check(not e.travel(id),'Cannot replay a node or start twice')
		if c.g.phase=='battle':
			var predicted=e.encounter(id)
			var enemy_units=c.g.battle.units.filter(func(u):return u.side=='enemy')
			check(enemy_units.size()==predicted.roster.size(),'Intel equals actual enemy count')
			for u in enemy_units: check(is_equal_approx(u.hp,c.enemies[u.type].hp*predicted.health),'Intel equals actual enemy HP')
			var won = fight(c)
			if won: actual_wins+=1
			else:
				# A deterministic test strategy is not a guarantee that every deck wins.
				# Verify defeat/retry, then use an explicit result fixture to test the rest of the route.
				print('BALANCE SAMPLE LOST at ',id,': ',c.g.buildings,' upgrades=',c.g.upgrades)
				check(e.settle() and not e.state.reward_due,'Actual defeat returns to map without reward')
				check(e.travel(id),'Defeated city can be retried')
				c.finish(true);settlement_fixtures+=1
				print('SETTLEMENT FIXTURE ONLY at ',id)
			check(e.settle(),'One settlement')
			check(not e.settle(),'No duplicate settlement')
		check(c.g.buildings==before_build and c.g.upgrades==before_upgrades,'Army and permanent growth preserved between scenes')
		check(e.state.current==id,'Map advances on success')
		if id=='266021': check(not e.can_travel('265883'),'Chosen route closes sibling branch')
		if c.g.phase=='reward': supply(c,e)
	check(e.state.finished and e.state.mode=='map','Whole Mediterranean completed in one run')
	check(not e.can_travel('727070'),'Final city cannot be farmed')
	c=Campaign.new(5)
	e=Expedition.new(c)
	c.g.defense=2
	c.g.orders={'shield':true}; c.g.armyShield=true
	e.travel('246349')
	check(c.g.defense==3,'Friendly port restores one life')
	check(c.g.armyShield and c.g.orders.has('shield'),'Peaceful port does not consume battle orders')
	c.skip();e.finish_supply()
	for loss in 3:
		if loss>0: check(e.travel('246349'),'Retry the same target')
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
	print('%d expedition checks, %d failures; actual city wins=%d; forced result fixtures=%d'%[checks,failures,actual_wins,settlement_fixtures])
	quit(1 if failures else 0)

extends SceneTree
const Campaign=preload('res://scripts/campaign.gd')
const Expedition=preload('res://scripts/expedition.gd')
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func opening():
	var c=Campaign.new(23)
	var e=Expedition.new(c)
	e.travel('246349');c.skip();e.finish_supply()
	return [c,e]
func _init():
	var pair=opening()
	var c=pair[0]
	var e=pair[1]
	for first in [1,2,3]:
		e.reset(first)
		for n in e.data.nodes:
			if n.roster==null: continue
			var waves=e.encounter(n.id).waves
			var expected=10 if n.kind in ['boss','final'] else 8 if n.kind=='elite' else 3 if n.step<=4 else 5
			check(waves.size()==expected,'Correct city length in every geographic rotation')
			check(waves[0].roster==n.roster,'First-wave scouting remains accurate')
			check(waves[1].roster!=waves[2].roster,'Later waves vary composition')
	pair=opening();c=pair[0];e=pair[1]
	# Explicit earned army fixture for multi-squad reserve and ID tests.
	c.g.buildings.append({'id':2,'type':'archer','cell':11,'level':1})
	c.g.battle.units=c.muster()
	var before=e.state.duplicate(true)
	var army=c.g.buildings.duplicate(true)
	var first=c.g.battle.initialEnemies
	# Force only the first wave clear, not the city's settlement.
	for u in c.g.battle.units:
		if u.side=='enemy': u.hp=0
	c.step(.1)
	check(c.g.phase=='battle' and c.g.battle.report==null,'First wave never completes city')
	check(c.g.battle.rest_remaining==3 and c.g.battle.waves_cleared==1,'Three second regroup starts')
	check(e.state==before and not e.settle(),'Rest cannot advance map or grant reward')
	c.step(0)
	check(c.g.battle.rest_remaining==3,'Zero simulation time cannot advance rest')
	c.g.battle.units[0].hp=0
	c.g.battle.units[1].hp=1
	for i in 180: c.step(1.0/60)
	c.step(1.0/60)
	check(c.g.battle.wave_index==1,'Next wave starts automatically')
	check(is_equal_approx(c.g.battle.units[0].hp,c.g.battle.units[0].maxHp*.7),'Routed squad receives partial reserves')
	check(c.g.battle.units[1].hp>=c.g.battle.units[1].maxHp*.7,'Surviving wounded squads never receive fewer reinforcements than routed squads')
	check(c.g.battle.initialEnemies==first+c.g.battle.waves[1].roster.size(),'Enemy counts accumulate only when deployed')
	for i in c.g.battle.units.size(): check(c.g.battle.units[i].id==i,'Projectile target IDs remain valid')
	check(c.g.battle.projectiles.is_empty(),'Old projectiles cannot hit new units')
	check(c.g.buildings==army,'Wave transitions do not mutate construction')
	# A loss during the second wave is one city loss, with only deployed enemies counted.
	for u in c.g.battle.units:
		if u.side=='ally': u.hp=0
	c.step(.1)
	check(not c.g.battle.report.won and c.g.defense==2,'Defeat costs one life')
	check(c.g.battle.report.wavesCleared==1 and c.g.battle.report.enemyLosses==first,'Defeat report excludes unspawned waves')
	check(e.settle() and not e.state.reward_due and e.state.current==before.current,'Defeat has no reward or travel progress')
	check(e.travel('246349') and c.g.battle.wave_index==0 and c.g.battle.rest_remaining==0,'Retry starts fresh at wave one')
	# Retry behavior above uses the earned-army fixture; measure the real opening separately.
	pair=opening();c=pair[0];e=pair[1]
	var limit=15000
	while c.g.phase=='battle' and limit>0:
		c.step(1.0/60);limit-=1
	check(limit>0 and c.g.battle.report.won,'Unupgraded starting army can clear small opening city')
	print('BASE OPENING seconds=',snapped(c.g.battle.time,.1))
	check(c.g.battle.report.wavesCleared==3,'Actual combat clears every wave')
	check(c.g.battle.report.enemyLosses==3,'Report includes every defeated wave')
	check(e.settle() and c.g.phase=='reward' and e.state.current=='246349','City victory advances and grants one reward')
	check(not e.settle(),'City cannot be settled twice')
	# Same real simulation across longer cities; no 75-second city-wide timeout.
	for count in [5,8,10]:
		c=Campaign.new(1);c.skip()
		var w={'roster':['enemy','enemy','archer'],'health':1.12,'attack':1.0}
		var waves=[]
		for i in count: waves.append(w.duplicate(true))
		c.g.expedition_wave=w.duplicate(true);c.g.expedition_wave.waves=waves
		c.g.buildings[0].level=3
		c.g.buildings.append({'id':2,'type':'archer','cell':11,'level':2})
		c.g.buildings.append({'id':3,'type':'siege','cell':16,'level':1})
		c.start();limit=60000
		while c.g.phase=='battle' and limit>0:
			c.step(1.0/60);limit-=1
		check(limit>0 and c.g.battle.report.won,'Real multiwave combat resolves '+str(count))
		check(c.g.battle.report.wavesCleared==count and c.g.history.size()==1,'One report after all waves '+str(count))
		check(c.g.battle.report.enemyLosses==count*3,'Cumulative report '+str(count))
		if count==10: check(c.g.battle.time>75,'Long cities are not stopped by the old total timeout')
	print('%d city-wave checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)

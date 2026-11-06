extends SceneTree
const Campaign=preload('res://scripts/campaign.gd')
const Formation=preload('res://scripts/formation.gd')
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;printerr('FAIL: '+message)
func reward(c,id):
	c.g.phase='reward';c.g.offerYear=c.g.round;c.g.offered=[id]
	return c.choose(id)
func _init():
	var c=Campaign.new(23)
	check(c.available('training'),'Drill yard is available for adjacency builds')
	for type in ['legion','archer','spear','guard','cavalry']:
		c=Campaign.new(23);c.g.buildings=[]
		for level in range(1,4):
			check(reward(c,type) and c.place(6),'Deploy/upgrade '+type+' '+str(level))
			var b=c.building_at(6)
			check(b.level==level and c.g.buildings.size()==1,'Upgrade keeps one occupied tile')
			var u=c.muster().filter(func(v):return v.side=='ally')[0]
			check(u.soldierCount==([4,6,8] if type=='cavalry' else [6,9,12])[level-1],'Visible population follows level')
			check(Vector2(u.x,u.y).is_equal_approx(Formation.battle_position(6)),'Actual squad starts in its own tile')
			check(is_equal_approx(u.maxHp/u.soldierCount,c.types[type].hp/Formation.count(type,1)),'Upgrade adds soldiers, not health per soldier')
		check(reward(c,type) and not c.place(6),'Cannot upgrade past III')
		check(c.place(7),'Level III still permits another legion')
	for id in c.cards:
		if c.types.has(id):continue
		c=Campaign.new(23)
		c.g.buildings=[]
		for type in ['legion','archer','siege','medic','cavalry','spear']:
			c.g.buildings.append({'id':c.g.buildings.size()+1,'cell':c.g.unlocked_cells[c.g.buildings.size()],'type':type,'level':1})
		if id=='oilShots':c.g.upgrades.fireArrows=1
		for level in range(1,4):
			check(reward(c,id) and c.rank(id)==level,'Card upgrades to level '+str(level)+': '+id)
			for language in ['zh','en']:
				var copy=c.card_copy(id,language,level)
				check(not copy.text.contains('{') and not copy.impact.contains('{'),'Resolved copy '+id)
		if c.cards[id].kind=='Battle order':
			check(reward(c,id) and c.rank(id)==3,'Max order reusable, never reaches IV')
			c.start();c.finish(true);c.next_year()
			check(c.rank(id)==3 and c.order_rank(id)==0,'Order mastery persists; activation expires')
		else:check(not c.available(id) and not reward(c,id),'Permanent max card leaves reward pool')
	# Exact continuity from camp through march; no attacks or position jumps during departure.
	c=Campaign.new(1);c.skip();var before=c.muster();c.start()
	check(before==c.g.battle.units,'Starting battle preserves the preview positions')
	for i in 32:
		c.step(.1)
		check(c.g.battle.events.is_empty() and c.g.battle.projectiles.is_empty(),'No attacks before deployment finishes')
		for u in c.g.battle.units:
			if u.side!='ally':continue
			var expected:Vector2=u.deployFrom.lerp(u.deployTo,minf(1,(i+1)/32.0))
			check(Vector2(u.x,u.y).distance_to(expected)<.001,'No out-of-bounds clamp/teleport in march')
	c.step(.1)
	check(c.g.battle.units.any(func(u):return u.moving),'Combat starts after departure')
	# Every order level changes its actual mechanic.
	for level in range(1,4):
		c=Campaign.new(9)
		c.g.buildings.append({'id':2,'type':'archer','cell':11,'level':1})
		c.g.upgrades={'shield':level,'testudo':level,'rally':level,'volley':level}
		c.g.orders={'shield':true,'testudo':true,'rally':true,'volley':true}
		var units=c.muster();var infantry=units.filter(func(u):return u.type=='legion' and u.side=='ally')[0]
		check(infantry.shield==40*level,'Shield scales at '+str(level))
		check(is_equal_approx(infantry.attack,14*(1+.25*level)),'Rally scales at '+str(level))
		check(is_equal_approx(c.testudo_damage(infantry.testudoRank),.7-.1*level),'Testudo damage reduction scales')
		check(is_equal_approx(c.stats(c.building_at(11)).interval,1.2/(1+.4*level)),'Volley scales')
	# Populations and functional buildings survive a full city without changing grid state.
	c=Campaign.new(9);c.skip();var buildings=c.g.buildings.duplicate(true);c.start()
	var limit=12000
	while c.g.phase=='battle' and limit>0:c.step(1.0/60);limit-=1
	check(limit>0 and c.g.battle.report!=null,'Normal battle resolves after marching')
	check(c.g.buildings==buildings,'Combat does not erase or move deployment cards')
	print('%d legion/card progression checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)

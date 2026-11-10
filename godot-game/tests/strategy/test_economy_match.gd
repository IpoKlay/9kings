extends SceneTree
const Battle=preload('res://scripts/strategy/battle.gd')
func _init():
	var r=Battle.new(false)
	var enemy_town=r.buildings.filter(func(b):return b.side=='enemy' and b.kind=='town')[0]
	var history=[]
	for frame in 36000:
		if r.phase!='battle':break
		if frame%120==0:
			var villagers=r.alive('ally').filter(func(u):return u.unit_type=='villager')
			for u in villagers:
				if u.soldiers[0].has('job'):continue
				var resource=[1,0,8][u.id%3]
				if r.resources[resource].remaining<=0:resource=2 if resource==1 else 9 if resource==0 else 8
				r.gathering([Vector2i(u.id,0)],resource)
			if villagers.size()<9 and r.buildings[0].queue.is_empty():r.train('villager',0)
			if r.elapsed>45 and r.level<3 and r.research_queue.is_empty():r.research('promotion',1)
			if r.buildings[1].queue.size()<2:r.train('shield' if frame%360 else 'spear',1)
			if r.population()>r.population_cap()-8 and villagers.size()>0 and not r.buildings.any(func(b):return b.kind=='house' and b.remaining>0):
				r.build('house',Vector2(1800+(r.population_cap()-40)*5,2790),[Vector2i(villagers[0].id,0)])
			if r.elapsed>160:
				var army=r.alive('ally').filter(func(u):return u.unit_type in ['shield','spear'])
				var ids=army.map(func(u):return Vector2i(u.id,0))
				if not ids.is_empty():r.assault_building(ids,enemy_town)
		r.step(1./60);r.events.clear();r.advance_casualties(1./60)
		if frame%3600==0:history.append({'time':int(r.elapsed),'population':r.population(),'level':r.level,'food':int(r.stock.food),'enemy_town_hp':enemy_town.hp})
	print('ECONOMY MATCH ',JSON.stringify({'phase':r.phase,'seconds':r.elapsed,'level':r.level,'population':r.population(),'own_town_hp':r.buildings[0].hp,'enemy_town_hp':enemy_town.hp,'history':history}))
	quit(0 if r.phase=='victory' else 1)

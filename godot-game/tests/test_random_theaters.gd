extends SceneTree
const Campaign=preload('res://scripts/campaign.gd')
const Expedition=preload('res://scripts/expedition.gd')
var checks=0
var failures=0
var routes=0
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; printerr('FAIL: '+message)
func walk(e,id: String,path: Array):
	check(id not in path,'No cycles after rotating theaters')
	if id in path: return
	var route=path+[id]
	var children=e.next(id)
	if children.is_empty():
		routes+=1
		check(route.size()==46 and id==e.data.final,'Every rotated route completes all 45 stops')
		check(route.filter(func(key):return e.nodes[key].roster!=null).size()==36,'36 battles regardless of start')
		for goal in e.data.goals: check(goal in route,'All theater goals remain mandatory')
		return
	for child in children: walk(e,child,route)
func _init():
	var baseline=Expedition.new(Campaign.new(23))
	for first in [1,2,3]:
		var c=Campaign.new(23)
		var e=Expedition.new(c)
		e.reset(first)
		check(e.battlefield_act()==first and e.current_act()==first,'Initial geography matches draw')
		check(e.stage_order.size()==3 and e.stage_order.duplicate().size()==3,'Three continuous theaters')
		check(e.nodes[e.data.final].kind=='final','Last theater receives final objective')
		for node in e.data.nodes:
			if node.roster==null: continue
			var stage=e.stage_order.find(int(node.act))+1
			for original in baseline.data.nodes:
				if original.act==stage and original.step==node.step and original.lane==node.lane:
					var a=e.encounter(node.id)
					var b=baseline.encounter(original.id)
					check(a.roster.size()==b.roster.size() and a.health==b.health and a.attack==b.attack,'Equal stage size and multipliers; geographic tactics may differ')
		walk(e,e.data.start,[])
		var entry=e.departure_port()
		check(not e.can_travel(entry),'Starting port is transit only')
		var battle=e.destinations()[0]
		check(e.travel(battle) and e.battlefield_act()==first,'Deployment uses drawn theater')
		check(c.g.phase=='battle' and c.g.battle!=null and c.g.buildings.size()==1,'Infantry-only battle before first reward')
		var before=e.completed_steps()
		c.finish(false);e.settle()
		check(e.completed_steps()==before and e.can_travel(battle),'Defeat does not skip battle')
		check(c.g.defense==2,'Defeat costs one life')
	check(routes==1536,'512 complete routes for each starting theater')
	print('%d randomized-theater checks, %d routes, %d failures'%[checks,routes,failures])
	quit(1 if failures else 0)

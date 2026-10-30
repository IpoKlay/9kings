extends SceneTree
const Campaign = preload('res://scripts/campaign.gd')
const Expedition = preload('res://scripts/expedition.gd')
var checks = 0
var failures = 0
var routes = 0
var covered: Dictionary = {}
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr('FAIL: '+message)
func walk(e, id: String, route: Array):
	check(id not in route,'Graph is acyclic')
	if id in route: return
	var path = route + [id]
	covered[id] = true
	var children = e.next(id)
	if children.is_empty():
		routes += 1
		check(id==e.data.final,'Every branch reaches Alexandria')
		check(path.size()==46,'45 stops plus assembly on every route')
		for act in range(1,4):
			var steps = path.filter(func(key):return e.nodes[key].act==act)
			check(steps.size()==15,'Every theater has fifteen chosen stops')
			check(steps.filter(func(key):return e.nodes[key].roster!=null).size()==12,'Twelve battles in every theater')
			for i in steps.size(): check(e.nodes[steps[i]].step==i+1,'No depth skipped')
		for goal in e.data.goals: check(goal in path,'All theater bosses are mandatory')
		return
	for child in children: walk(e,child,path)
func _init():
	var c = Campaign.new(23)
	var e = Expedition.new(c)
	check(e.nodes.size()==e.data.nodes.size(),'Unique node IDs')
	for node in e.data.nodes:
		check(node.source.begins_with('https://pleiades.stoa.org/places/'),'Every location has a gazetteer reference')
		for field in ['name','name_en','history','history_en','title','title_en']:
			check(not node[field].is_empty(),'Bilingual content: '+node.id+' '+field)
		if node.roster!=null:
			for type in node.roster: check(c.enemies.has(type),'Existing native enemy type')
	walk(e,e.data.start,[])
	check(routes==512,'Nine binary forks produce 512 itineraries')
	check(covered.size()==55,'All 55 nodes reachable')
	# Retry an actual fork: defeat cannot switch to the alternative route.
	for id in ['246349','246369']:
		check(e.travel(id),'Approach first fork')
		if e.state.opening=='card': c.skip(); e.finish_supply()
		if c.g.phase=='battle': c.finish(true); e.settle()
		c.skip(); e.finish_supply()
	check(e.can_travel('266021') and e.can_travel('265883'),'Both fork arms accessible')
	check(e.travel('265883'),'Commit elite island branch')
	var predicted = e.encounter('265883')
	c.finish(false); e.settle()
	check(e.can_travel('265883') and not e.can_travel('266021'),'Defeat locks chosen branch')
	check(e.encounter('265883')==predicted,'Retry does not increase difficulty')
	check(e.completed_steps()==3,'Defeat adds no progress')
	print('%d route structure checks across %d itineraries, %d failures'%[checks,routes,failures])
	quit(1 if failures else 0)

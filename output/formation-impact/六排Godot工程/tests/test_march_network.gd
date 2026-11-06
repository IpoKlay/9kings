extends SceneTree
const Catalog=preload('res://scripts/data/catalog.gd')
const Campaign=preload('res://scripts/campaign.gd')
const Expedition=preload('res://scripts/expedition.gd')
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func _init():
	var paths=Catalog.data('generated/march_paths').edges
	var water=load('res://assets/expedition/shore_distance.png').get_image()
	for first in [1,2,3]:
		var c=Campaign.new(23);var e=Expedition.new(c);e.reset(first)
		check(e.stage_order[0]==first,'Random starting theater is retained')
		for edge in e.data.edges: check(paths.has(edge[0]+'>'+edge[1]),'Every rotated route has geographic waypoints')
		for source in e.march_choices:
			var branch=e.march_choices[source]
			for choice in branch.choices:
				c=Campaign.new(23);e=Expedition.new(c);e.reset(first)
				e.state.current=source;e.state.visited=[e.data.start,source];e.state.opening='done'
				check(e.destinations().size()==2 and e.can_travel(choice),'Two local branches can be chosen before commitment')
				check(e.preview_edges(choice)==[source+'>'+choice,choice+'>'+branch.merge],'Preview continues to the common merge')
				check(e.route_hint(int(e.nodes[source].act)).contains(e.node_text(branch.merge)),'Player can read where the branches rejoin')
				var sibling=branch.choices.keys().filter(func(id):return id!=choice)[0]
				check(e.travel(choice),'Branch enters actual native battle')
				c.finish(false);check(e.settle() and e.can_travel(choice) and not e.can_travel(sibling),'Failure cannot switch or farm the abandoned sibling')
				check(e.travel(choice),'Committed route supports retry')
				c.finish(true);check(e.settle(),'Chosen branch settles once')
				c.skip();e.finish_supply()
				check(e.can_travel(branch.merge) and not e.can_travel(sibling),'Only the forward merge remains after victory')
				check(e.travel(branch.merge),'Route rejoins at its key city')
				c.finish(true);e.settle();c.skip();e.finish_supply()
				check(not e.can_travel(sibling),'Merge never reopens the unchosen path')
	# Inland approach is an area marker; original city coordinates remain in the gazetteer.
	check(Catalog.data('generated/march_paths').visual_sites.has('344456_inland'),'Oea inland approach is separate from the coastal city')
	# Verify baked segments between port approaches. Endpoints may touch a harbor or inland Rome.
	for key in paths:
		var route=paths[key];var points=route.points
		var mismatch=0;var total=0
		for i in range(2,points.size()-1):
			var a=Vector2(points[i-1][0],points[i-1][1]);var b=Vector2(points[i][0],points[i][1])
			for t in range(1,maxi(2,ceili(a.distance_to(b)/8))):
				var p=a.lerp(b,float(t)/maxi(2,ceili(a.distance_to(b)/8)))*.5
				var wet=water.get_pixelv(Vector2i(p)).g>.5
				total+=1
				if wet!=(route.mode=='sea'):mismatch+=1
		check(total==0 or float(mismatch)/total<.03,'Schematic corridor follows its land/sea surface '+key)
	print('%d geographic branch checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)

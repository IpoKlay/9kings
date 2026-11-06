extends SceneTree
const C=preload('res://scripts/campaign.gd')
const E=preload('res://scripts/expedition.gd')
var checks=0
var failures=0
func check(ok,message):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func _init():
	for first in [1,2,3]:
		var c=C.new(23);var e=E.new(c);e.reset(first)
		for n in e.data.nodes:
			if n.roster==null:continue
			var encounter=e.encounter(n.id)
			check(encounter.roster==n.roster,'Scouting uses actual first wave '+n.id)
			check(e.encounter(n.id)==encounter,'Inspection is deterministic '+n.id)
			if e.doctrine_id(n.id)=='patrol':continue
			var profile=e.doctrines.profiles[e.doctrine_id(n.id)]
			var signature=profile.roster[1]
			for wave in encounter.waves:
				check(signature in wave.roster,'Every wave retains the advertised core '+n.id)
				check(wave.roster.size()==n.roster.size(),'Doctrine preserves stage force count '+n.id)
				var units=c.muster(wave).filter(func(u):return u.side=='enemy')
				check(units.map(func(u):return u.type).count(signature)==wave.roster.count(signature),'Real combat fields the scout profile '+n.id)
		for source in e.march_choices:
			var ids=e.march_choices[source].choices.keys()
			check(e.encounter(ids[0]).roster!=e.encounter(ids[1]).roster,'Two routes field distinct forces '+source)
			check(e.doctrine_id(ids[0])!=e.doctrine_id(ids[1]),'Tactical identity survives rotated start '+source)
			e.state.current=source;e.state.opening='done'
			check(e.briefing().choices==ids and not e.briefing().ahead,'Current fork compares both options')
			for edge in e.data.edges:
				if edge[1]==source and e.nodes[edge[0]].act==e.nodes[source].act:
					e.state.current=edge[0]
					check(e.briefing().ahead and e.briefing().choices==ids,'Preceding reward can scout the next fork')
		c.reset(23);e.reset(first)
		var start=e.destinations()[0]
		check(e.travel(start),'Infantry-only start enters battle')
		var steps=0
		while c.g.phase=='battle' and steps<20000:c.step(.05);steps+=1
		check(c.g.phase=='result' and c.g.battle.report.won,'Base infantry wins starting city '+str(first))
		print('OPENING ',first,' seconds=',c.g.battle.time)
	# Advice follows actual placed units, not merely a previously acquired order rank.
	var c=C.new(23);var e=E.new(c)
	check(e.response_cards('265823').owned.is_empty(),'No phantom anti-cavalry card at start')
	c.g.buildings.append({'id':99,'type':'spear','cell':7,'level':1})
	check(e.response_cards('265823').owned==['spear'],'Placed spearmen are identified')
	c.g.upgrades.shield=2
	check('shield' not in e.response_cards('265823').owned,'Consumed order is not advertised as ready')
	c.g.orders.shield=true
	check('shield' in e.response_cards('265823').owned,'Active order is advertised')
	print('%d tactical route checks, %d failures'%[checks,failures]);quit(1 if failures else 0)

extends SceneTree
const C=preload('res://scripts/campaign.gd')
const E=preload('res://scripts/expedition.gd')
const S=preload('res://scripts/data/run_store.gd')
var checks=0
var failures=0
func check(ok,msg):
	checks+=1
	if not ok:failures+=1;printerr('FAIL: ',msg)
func _init():call_deferred('run')
func restore(d):
	var c=C.new(0);var e=E.new(c);e.configure_route(d.first_act);c.g=d.campaign.duplicate(true);e.state=d.expedition.duplicate(true)
	return [c,e]
func run():
	if '--verify-disk' in OS.get_cmdline_user_args():
		var saved=S.read_run('/private/tmp/eagle-run-recovery-test.cfg')
		check(not saved.is_empty(),'Separate process reads previous checkpoint')
		if not saved.is_empty():
			var restored=restore(saved)
			check(restored[0].g.phase=='defeat' and restored[0].g.defense==0,'Separate process preserves terminal state')
		print(checks,' separate-process checks, ',failures,' failures');quit(1 if failures else 0);return
	var c=C.new(23);var e=E.new(c);e.reset(2)
	var target=e.destinations()[0]
	check(e.travel(target),'start')
	var active=c.g.duplicate(true)
	var d=S.snapshot(c,e)
	check(c.g==active,'Snapshot cannot mutate live combat')
	check(S.valid(d),'Battle checkpoint valid')
	var pair=restore(d);var cc=pair[0];var ee=pair[1]
	check(ee.can_travel(target) and not ee.can_reorganize(),'Reload locks same destination without granting defeat reward')
	check(ee.travel(target) and cc.g.battle.units==active.battle.units,'Identical first-wave army and enemies')
	c.finish(false)
	check(S.snapshot(c,e).expedition.mode=='camp','Unconfirmed loss restores regroup camp')
	check(e.settle(),'settle loss')
	check(e.reorganize(),'first recovery')
	d=S.snapshot(c,e);pair=restore(d);cc=pair[0];ee=pair[1]
	check(cc.offers()==['shield','testudo','rally'],'Recovery choices preserved')
	var rank=cc.rank('shield')
	check(cc.choose('shield') and cc.rank('shield')==rank and cc.order_rank('shield')==1,'Temporary order without permanent rank')
	ee.finish_supply();check(not ee.reorganize(),'No second claim')
	check(ee.travel(target),'retry');cc.finish(false);ee.settle()
	check(cc.order_rank('shield')==0 and not ee.reorganize(),'Consumed on loss, city limit preserved')
	c=C.new(23);e=E.new(c);e.reset(1);e.travel(e.destinations()[0]);c.finish(false);e.settle()
	c.g.upgrades.shield=3;e.reorganize()
	check(c.choose('shield') and c.rank('shield')==3 and c.order_rank('shield')==1,'Existing rank III remains unchanged, temporary effect stays rank I')
	c=C.new(23);e=E.new(c);e.reset(1);e.travel(e.destinations()[0]);c.finish(false);e.settle();e.reorganize();c.skip();e.finish_supply()
	check(not e.can_reorganize() and c.g.temporary_orders.is_empty(),'Skipping recovery forfeits grant without applying an order')
	# Elite test uses explicit victory solely to test the reward transaction.
	c=C.new(47);e=E.new(c);e.state.opening='done';e.state.current='246369';e.state.visited=['423025','148127','246349','246369']
	check(e.travel('265883'),'elite')
	c.finish(true);var live=c.g.duplicate(true);d=S.snapshot(c,e)
	check(c.g==live and c.g.phase=='result','Pending result snapshot does not settle live game')
	check(S.valid(d) and d.campaign.phase=='reward','Victory resumes at unclaimed reward')
	check(d.campaign.reward_context=='elite' and d.campaign.reward_rerolls==1,'Elite context persisted')
	pair=restore(d);cc=pair[0];ee=pair[1]
	check(cc.offers().any(func(id):return cc.cards[id].kind=='Permanent'),'Elite guarantee')
	check(cc.reroll_reward(),'Redraw once')
	check(cc.offers().any(func(id):return cc.cards[id].kind=='Permanent'),'Guarantee after redraw')
	d=S.snapshot(cc,ee)
	var path='/private/tmp/eagle-run-recovery-test.cfg'
	check(S.write_run(path,d)==OK,'Write atomic checkpoint')
	check(S.read_run(path)==d,'Exact state reload')
	pair=restore(S.read_run(path));cc=pair[0];ee=pair[1]
	check(not cc.reroll_reward(),'Reload cannot refill redraw')
	var offered=cc.offers();check(offered==d.campaign.offered,'Reload cannot reroll cards')
	check(cc.choose(offered[0]),'Choose persisted card')
	if cc.g.phase=='place':
		d=S.snapshot(cc,ee);check(S.valid(d),'Pending placement serializes')
		pair=restore(d);cc=pair[0];ee=pair[1];check(cc.place(6),'Pending placement resumes')
	ee.finish_supply();d=S.snapshot(cc,ee);check(S.write_run(path,d)==OK,'Save selection')
	check(S.read_one(path+'.bak')!= {},'Good backup retained')
	FileAccess.open(path,FileAccess.WRITE).store_string('broken')
	check(not S.read_run(path).is_empty(),'Corrupt primary falls back')
	var invalid=d.duplicate(true);invalid.campaign.buildings[0].type='missing'
	check(not S.valid(invalid),'Unknown type rejected')
	for bad in ['bad',{},1.5]:
		invalid=d.duplicate(true);invalid.campaign.buildings[0].level=bad
		check(not S.valid(invalid),'Malformed building level rejected')
	# Actual three-wave opening, then disk roundtrip at the victory boundary.
	c=C.new(23);e=E.new(c);e.reset(1);e.travel(e.destinations()[0])
	while c.g.phase=='battle':c.step(1.0/60)
	check(c.g.battle.report.won,'Actual opening battle won')
	d=S.snapshot(c,e);check(S.write_run(path,d)==OK and S.read_run(path)==d,'Actual combat result persists')
	pair=restore(d);cc=pair[0];ee=pair[1]
	cc.skip();ee.finish_supply();cc.g.expansion_credits=1
	check(cc.expand(0) and cc.relocate(1,0),'Expand and reposition')
	d=S.snapshot(cc,ee);check(S.write_run(path,d)==OK and S.read_run(path).campaign.buildings[0].cell==0,'Expanded layout persists')
	# No eligible permanent remains: keep a valid ordinary choice, never a capped card.
	cc.g.phase='reward';cc.g.reward_context='elite';cc.g.offerYear=0
	for id in cc.cards:
		if cc.cards[id].kind=='Permanent':cc.g.upgrades[id]=3
	check(cc.offers().size()==3 and cc.offers().all(func(id):return cc.available(id)),'Exhausted upgrades still produce usable cards')
	# A terminal loss stays terminal after restarting.
	c=C.new(23);e=E.new(c);e.reset(3);e.travel(e.destinations()[0]);c.g.defense=1;c.finish(false)
	d=S.snapshot(c,e);check(S.write_run(path,d)==OK,'Terminal loss saves')
	pair=restore(S.read_run(path));cc=pair[0];ee=pair[1]
	check(cc.g.phase=='defeat' and cc.g.defense==0 and not ee.can_reorganize(),'Terminal loss cannot become a free retry')
	print(checks,' save/recovery/elite checks, ',failures,' failures');quit(1 if failures else 0)

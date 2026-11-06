extends SceneTree
const Campaign=preload('res://scripts/campaign.gd')
const Expedition=preload('res://scripts/expedition.gd')
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;printerr('FAIL: '+message)
func run_fight(c):
	var ticks=0
	while c.g.phase=='battle' and ticks<60000:c.step(1.0/60);ticks+=1
	check(ticks<60000 and c.g.battle.report!=null,'Battle finishes within its wave budget')
func force_card(c,id):
	c.g.phase='reward';c.g.offered=[id];c.g.offerYear=c.g.round
	return c.choose(id)
func _init():
	for act in [1,2,3]:
		var c=Campaign.new(23);var e=Expedition.new(c);e.reset(act)
		check(c.g.buildings.size()==1 and c.g.buildings[0].type=='legion','Only infantry at game start')
		check(c.g.unlocked_cells.size()==9 and c.g.buildings[0].cell==12,'Central 3x3 with infantry at center')
		check(e.travel(e.destinations()[0]) and c.g.phase=='battle' and e.state.opening=='done','Destination immediately starts infantry battle')
		check(c.g.cities_captured==0 and c.g.expansion_credits==0,'Friendly departure port does not count as a captured city')
		check(c.g.offered.is_empty() and not e.state.reward_due,'No opening card or bonus facility')
		check(c.g.battle.units.filter(func(u):return u.side=='ally').size()==1,'First battle has exactly one allied squad')
		check(not c.expand(1) and not c.relocate(1,6),'Battle blocks expansion and relocation')
		run_fight(c)
		print('Opening act ',act,': ',snappedf(c.g.battle.time,.1),'s; won=',c.g.battle.report.won)
		check(c.g.battle.report.won and c.g.battle.report.wavesCleared==3,'Infantry can beat all three opening waves')
		check(c.g.battle.time>25,'Opening is not a few-second battle')
		check(e.settle() and c.g.phase=='reward' and c.g.cities_captured==1,'First cards arrive only after first city victory')
		check(not e.settle() and c.g.cities_captured==1,'Double settlement cannot award extra expansion progress')
		check(c.offers().any(func(id):return c.is_troop(id)),'Early rewards offer at least one troop option')
	var c=Campaign.new(1)
	check(c.expansion_candidates().size()==16 and [0,4,20,24].all(func(cell):return cell in c.expansion_candidates()),'All 16 perimeter cells, including corners, are offered')
	check(not c.expand(1),'Expansion requires earned credit')
	c.record_capture();c.record_capture()
	check(c.g.expansion_credits==0,'Two captured cities do not award an expansion')
	c.record_capture()
	check(c.g.expansion_credits==1,'Third captured city awards exactly one extra tile')
	var hand=c.offers();c.g.phase='reward'
	check(c.expand(1) and c.g.unlocked_cells.size()==10 and c.g.expansion_credits==0,'Expansion consumes one credit and opens one cell')
	check(c.g.phase=='reward' and c.offers()==hand,'Expansion does not consume or reroll the card reward')
	check(0 in c.expansion_candidates() and not c.expand(1),'Unchosen corners remain available; repeat unlock is rejected')
	check(force_card(c,'archer') and not c.place(0),'Locked cells reject construction')
	check(c.place(1),'Newly unlocked cell accepts a troop')
	check(not c.adjacent(4,5) and c.adjacent(6,7) and not c.adjacent(6,12),'Adjacency never wraps or counts diagonal cells')
	c.g.phase='prepare'
	check(c.relocate(1,13),'Existing troops can be repositioned between cities')
	var old_id=c.building_at(1).id
	check(c.relocate(1,1) and c.building_at(13).id==old_id,'Occupied destination swaps without deleting either unit')
	check(not c.relocate(1,0),'Relocation cannot bypass locked tiles')
	c=Campaign.new(1)
	c.g.buildings=[{'id':1,'type':'legion','cell':12,'level':1},{'id':2,'type':'training','cell':11,'level':2},{'id':3,'type':'medic','cell':7,'level':1}]
	var b=c.building_at(12)
	check(is_equal_approx(c.stats(b).attack,21) and is_equal_approx(c.stats(b).hp,172.5),'Orthogonal support changes actual combat stats')
	c.g.buildings.append({'id':4,'type':'training','cell':13,'level':1})
	check(is_equal_approx(c.stats(b).attack,21),'Duplicate support uses strongest rather than multiplying')
	c.g.buildings[1].cell=6;c.g.buildings[2].cell=8;c.g.buildings[3].cell=18
	check(is_equal_approx(c.stats(b).attack,14) and is_equal_approx(c.stats(b).hp,150),'Diagonal support grants no bonus')
	c.g.buildings=[{'id':1,'type':'legion','cell':12,'level':1},{'id':2,'type':'training','cell':11,'level':2}]
	check(is_equal_approx(c.site_bonuses({'type':'legion','cell':11},12).attack,.5),'Swap preview uses support at its future position')
	c.relocate(1,11)
	check(is_equal_approx(c.site_bonuses(c.building_at(11)).attack,.5),'Actual swap matches preview')
	c.g.buildings=[{'id':1,'type':'legion','cell':13,'level':1},{'id':2,'type':'archer','cell':11,'level':1}]
	var before=c.muster();var infantry=before.filter(func(u):return u.side=='ally' and u.type=='legion')[0]
	var archer=before.filter(func(u):return u.side=='ally' and u.type=='archer')[0]
	check(infantry.deployTo.x>archer.deployTo.x,'Forward tile places infantry ahead of rear archers')
	c.relocate(1,11);var after=c.muster()
	infantry=after.filter(func(u):return u.side=='ally' and u.type=='legion')[0];archer=after.filter(func(u):return u.side=='ally' and u.type=='archer')[0]
	check(infantry.deployTo.x<archer.deployTo.x,'Swapping positions changes battle order; no automatic role sorting')
	c.start();check(c.g.battle.units==after,'Camp positions are continuous at battle start')
	c=Campaign.new(1)
	while c.g.unlocked_cells.size()<25:
		c.g.expansion_credits=1
		check(c.expand(c.expansion_candidates()[0]),'Each remaining perimeter cell can be unlocked')
	check(c.expansion_candidates().is_empty() and not c.expand(25),'Maximum 5x5 cannot grow beyond the outer ring')
	c.g.buildings=[]
	for cell in c.g.unlocked_cells:c.g.buildings.append({'id':cell+1,'type':'legion','cell':cell,'level':3})
	check(not c.available('archer') and not force_card(c,'archer'),'A full camp never offers an unplaceable new troop')
	c.reset(1)
	check(c.g.unlocked_cells.size()==9 and c.g.cities_captured==0 and c.g.expansion_credits==0,'New expedition resets expansion and captures')
	print('%d camp expansion checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)

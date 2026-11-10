extends SceneTree
const Rules=preload('res://scripts/previews/cavalry_depth_rules.gd')
const Production=preload('res://scripts/tactical/whiteboard_battle.gd')
var failures=0
var checks=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred('run')
func run():
	var summaries={}
	for mode in ['flank','shield','pikes']:
		var r=Rules.new(false)
		r.config.individual_charge.speed=360.
		r.config.individual_charge.follow_through=200.
		r.config.individual_charge.slow_per_hit=.08
		r.setup(mode)
		check(r.rider_ids.size()==24 and r.defender_ids.size()==40,mode+': fixed 64 people')
		check(r.structures.is_empty(),mode+': no siege structures')
		check(r.launch(),mode+': shared C command accepted')
		for key in r.rider_ids:
			var actor=r.units[key.x].soldiers[key.y]
			var nearest=INF
			for defender in r.defender_ids:
				var point: Vector2=r.initial_feet[defender]
				nearest=minf(nearest,point.distance_to(Geometry2D.get_closest_point_to_segment(point,actor.position,actor.charge_run.goal)))
			check(nearest<=r.Soldiers.individual(r,r.units[key.x]).range,mode+': rider '+str(key)+' initial lane reaches defenders')
		var start=r.units[4].soldiers[0].position
		r.step(0.)
		check(r.units[4].soldiers[0].position==start,mode+': zero time preserves position')
		var empty_followup=false
		for frame in 720:
			r.step(1./60.);r.events.clear()
			for key in r.rider_ids:
				var actor=r.units[key.x].soldiers[key.y]
				if actor.has('charge_end') and actor.personal_order=='move':empty_followup=true
			if frame%120==0:await process_frame
		check(not empty_followup,mode+': no automatic move farther into empty ground after charging')
		var pairs={};var first={};var ended={};var through=0
		for hit in r.contact_log:
			var key=str(hit.rider)+str(hit.victim)
			check(not pairs.has(key),mode+': no repeated rider/victim charge damage')
			pairs[key]=true
			var rank=hit.rider[0]
			if not first.has(rank):first[rank]=hit.time
		for key in r.rider_ids:
			var actor=r.units[key.x].soldiers[key.y]
			check(not actor.has('charge_run'),mode+': charge has finite end')
			check(r.bounds.has_point(actor.position),mode+': movement stays in battlefield')
			var touched=r.contact_log.any(func(hit):return hit.rider==[key.x,key.y])
			check(touched or r.entered_defense.has(key),mode+': rider '+str(key)+' actually contacts or enters the original defensive footprint')
			var reason=actor.get('charge_end',{}).get('reason','dead')
			ended[reason]=ended.get(reason,0)+1
			if reason=='through':through+=1
		if mode=='flank':
			check(first.size()==3 and first[4]<first[5] and first[5]<first[6],'Front rank hits before both following ranks')
			check(through>=2,'At least two actual contacting riders finish finite follow-through')
		if mode=='pikes':check(ended.get('pike',0)>=8,'Braced pikes stop at least the first cavalry rank')
		summaries[mode]={'hits':r.contact_log.size(),'first_by_rank':first,'ends':ended}
	var production=Production.new(false)
	check(production.config.individual_charge.speed==240.,'Preview speed does not mutate production balance')
	for kind in ['legion','cavalry']:
		var stats=production.config.types[kind]
		for slot in int(stats.files):check(production.Contact.slot_offset(kind,stats,slot).y==0.,'Production stays single rank')
	var retry=Rules.new(false);retry.setup()
	check(retry.contact_log.is_empty() and retry.exit_pending.is_empty(),'Fresh preview has no old contacts or exit orders')
	print(JSON.stringify(summaries));print('Cavalry depth: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)

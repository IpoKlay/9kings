extends SceneTree
const Motion=preload('res://scripts/tactical/corpse_motion.gd')
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred('run')
func motion(kind='swordsman',velocity=Vector2(60,10),attacker=Vector2(40,20)):
	var m=Motion.new();m.setup(kind,Vector2.from_angle(.7),velocity,attacker,12.,712);return m
func run():
	var m=motion()
	check(m.direction.is_equal_approx(Vector2(40,20).normalized()),'Last valid attacker determines the impact direction')
	check(motion('swordsman',Vector2(0,-30),null).direction==Vector2.UP,'No attacker uses normal velocity, not facing')
	check(motion('swordsman',Vector2.ZERO,null).direction==motion('swordsman',Vector2.ZERO,null).direction,'Stationary deaths use a reproducible isolated cosmetic random stream')
	check(motion('swordsman',Vector2.ZERO,Vector2.ZERO).direction==Vector2.ZERO,'Coincident attacker remains zero direction, matching reference')
	for sample in [[0.,0.],[.06,.5],[.12,1.],[1.35,1.],[2.175,.5],[3.,0.]]:
		m.age=sample[0];check(is_equal_approx(m.opacity(),sample[1]),'Reference opacity at '+str(sample[0]))
	for kind in Motion.definitions.types:
		m=motion(kind);var type:int=Motion.definitions.types[kind]
		var count=0 if type==43 else 8 if type==46 else 17 if type in [6,12,13,26,27,45] else 11
		check(m.x.size()==count and m.rest.size()==count,kind+' uses the observed skeleton topology')
		check(m.blood.size()==(0 if type in [41,42,43,45] else 12),kind+' uses the correct blood/scatter distinction')
		check(m.equipment.has('shield')==(type in [0,2,40,42]),kind+' detaches a shield only for observed types')
		var initial=m.x.duplicate();m.advance(0);check(m.x==initial and m.age==0,kind+' zero delta cannot move a cosmetic body')
		for frame in 150:m.advance(1./60)
		check(Array(m.x).all(func(v):return is_finite(v)) and m.opacity()>0,kind+' remains finite before expiry')
		m.advance(.6);check(m.opacity()==0,kind+' ends after three simulation seconds')
	m=motion();var e:Dictionary=m.equipment.weapon;var v:Vector2=(e.point-e.old)*.94;var initial_point:Vector2=e.point;var initial_angle:float=e.angle
	m.advance(1./60)
	check(e.point.is_equal_approx(initial_point+v) and is_equal_approx(e.angle,initial_angle+(v.x+v.y)*.02),'Detached weapon obeys independent drag and angular update')
	check(is_equal_approx(m.pool_radius,4.8) and motion('skeleton_archer').pool_radius==0,'Blood pool radius and skeleton omission follow source')
	check(motion('skeleton_archer').links.is_empty() and motion('death_rider').angles.is_empty(),'Skeletons scatter instead of remaining constrained')
	check(motion('wraith').burst.size()==40 and motion('wraith').x.is_empty(),'Wraith uses forty burst fragments and no humanoid corpse')
	var fps_results=[]
	for fps in [30,60,120]:
		m=motion()
		for frame in fps:m.advance(1./fps)
		fps_results.append({'fps':fps,'head':m.point(0),'opacity':m.opacity(),'age':m.age})
	check(fps_results[0].head!=fps_results[2].head,'Reference per-render visual drag intentionally differs across render rates')
	check(is_equal_approx(fps_results[0].age,fps_results[2].age) and fps_results[0].opacity==fps_results[2].opacity,'Lifetime still follows elapsed simulation time across rates')
	var r=Battle.new();r.units.clear();r.spawn('legion','ally',Vector2(1000,1000));r.hurt(r.units[0],100000.,'',0.,0);r.record_casualty(r.units[0],0)
	var moving=r.units[0].soldiers[0];moving.velocity=Vector2(0,80);moving.last_attacker=Vector2i(-1,-1);r.record_casualty(r.units[0],0)
	var recorded=r.casualties.back().motion;check(recorded.direction==Vector2.DOWN and absf((recorded.y[2]-recorded.old_y[2])-2.16)<.00001,'Scene records unprojected velocity, so vertical and horizontal corpse impulses use identical world units')
	r.phase='victory';var combat_time=r.elapsed;var units=r.units.duplicate(true)
	for frame in 181:r.advance_casualties(1./60)
	check(r.casualties.is_empty() and r.elapsed==combat_time and r.units==units,'Post-result body cleanup cannot resume combat or mutate soldiers')
	for i in 190:r.record_casualty(r.units[0],0)
	r.collect_casualties();check(r.casualties.size()==190,'Large simultaneous deaths are not truncated by the old180-body limit')
	var config=r.config;var kinds={}
	for kind in config.types:kinds[kind]=true
	for variant in config.unit_variants.values():kinds[variant.get('art',variant.kind)]=true
	var parts:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://data/presentation/corpse_parts.json'))
	for kind in kinds:
		check(parts.has(kind) and parts[kind].size()==8,kind+' has eight authored rigid-piece bearings')
		for side in ['ally','enemy']:check(ResourceLoader.exists('res://assets/rts-corpses/'+kind+'_'+side+'.png'),kind+' '+side+' has imported corpse artwork')
	FileAccess.open('res://../output/sword-banner-reference/corpse-motion/visual-fps.json',FileAccess.WRITE).store_string(JSON.stringify(fps_results,'\t'))
	print('Corpse motion: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)

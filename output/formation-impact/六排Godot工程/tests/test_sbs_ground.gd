extends SceneTree
## Check distinct regional floors and capture actual deployment/battle scenes.
const OUT='res://../output/three-theater-terrain/'
var checks=0
var failures=0
var app
func _init():call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;printerr('FAIL: '+message)
func capture(id: String):
	await process_frame;await process_frame
	RenderingServer.force_draw()
	var image=root.get_texture().get_image()
	check(image.save_png(OUT+id+'.png')==OK,'Save native screenshot '+id)
	return image
func run():
	if DisplayServer.get_name()=='headless':
		printerr('Ground integration check requires the native renderer.');quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var preset=preload('res://scripts/data/catalog.gd').presentation('environment')
	check(preset.ground_overlays==['','',''],'No central grass island or brown camp overlay remains')
	check(preset.backgrounds==['environments/iberia-grass','environments/africa-sand','environments/east-coastal'],'All three theaters use their approved regional backgrounds')
	var reference_tone=Vector3.ZERO
	for act in [1,2,3]:
		var ground=load('res://assets/'+preset.backgrounds[act-1]+'.png').get_image()
		check(absf(float(ground.get_width())/ground.get_height()-16.0/9)<.01,'Theater %d retains the original aspect ratio'%act)
		# Exposed floor samples avoid the original perimeter trees, stone paving and water.
		var patches=[Vector2(180,240),Vector2(520,170),Vector2(950,250),Vector2(1510,280),Vector2(1740,580),Vector2(1550,1000),Vector2(950,1010),Vector2(790,930),Vector2(550,360),Vector2(975,650),Vector2(1100,400)]
		if act==2:patches[5]=Vector2(1420,920) # The other coordinate falls inside a palm crown.
		var tone=Vector3.ZERO
		for p in patches:
			var matched=0
			for y in range(-12,13,3):
				for x in range(-12,13,3):
					var uv=(p+Vector2(x,y))/Vector2(1920,1080)
					var c=ground.get_pixelv(Vector2i(uv*Vector2(ground.get_size())))
					tone+=Vector3(c.r,c.g,c.b)
					if act==2:
						if c.r>c.g*1.05 and c.g>c.b*1.2:matched+=1
					elif c.g>c.r*1.02 and c.g>c.b*1.10:matched+=1
			check(matched>=65,'Theater %d regional floor near %s'%[act,p])
		tone/=patches.size()*81.0
		if act==1:reference_tone=tone
		elif act==2:check(tone.distance_to(reference_tone)>.25,'North African sand is visibly distinct from Iberian grass')
		else:check(tone.z-reference_tone.z>.07 and tone.y-reference_tone.y>.05,'Eastern coastal grass is cooler and lighter than Iberian grass')
	root.size=Vector2i(1920,1080)
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-sbs-integrated.cfg'
	root.add_child(app);current_scene=app;app.set_process(false)
	app.music.set_volume(0,0)
	app.sound.enabled=false;app.sound.stop();app.sound.set_process(false)
	for act in [1,2,3]:
		app.restart_expedition(act);app.expedition_map.settle_entry()
		app.travel_to(app.expedition.destinations()[0])
		# Explicit full-camp rendering fixture after an earned city reward.
		app.campaign.finish(true);app.advance()
		app.campaign.g.unlocked_cells=range(25)
		app.campaign.g.buildings=[]
		for row in 3:
			for col in 3:
				app.campaign.g.buildings.append({'id':row*4+col+1,'cell':row*4+col,'type':['legion','archer','cavalry'][col],'level':row+1})
		app.campaign.g.buildings.append({'id':4,'cell':3,'type':'siege','level':1})
		app.campaign.g.buildings.append({'id':8,'cell':7,'type':'medic','level':2})
		app.campaign.g.buildings.append({'id':12,'cell':11,'type':'siege','level':3})
		app.campaign.g.nextId=13
		app.campaign.g.offerYear=app.campaign.g.round
		app.campaign.g.offered=['legion','medic','testudo'];app.render_ui()
		app.card_hand.input_enabled=false
		await create_timer(.6).timeout
		var before=app.campaign.g.duplicate(true)
		await capture('%d-deployment'%act)
		check(app.campaign.g==before,'Rendering does not modify campaign state')
		check(app.world.environment.surface.texture.resource_path=='res://assets/'+preset.backgrounds[act-1]+'.png','The actual scene loads its regional background')
		app.campaign.skip();app.campaign.g.orders.testudo=true;app.campaign.g.upgrades.testudo=2
		app.expedition.finish_supply();app.continue_expedition();app.travel_to(app.expedition.destinations()[0]);app.render_ui()
		check(app.campaign.g.phase=='battle','The actual battle can start')
		for frame in 220:
			app.campaign.step(1.0/60);app.world.tick(1.0/60)
			app.world.events(app.campaign.g.battle.events)
			if frame in [95,219]:await capture('%d-march'%act if frame==95 else '%d-battle'%act)
		check(app.campaign.g.battle.time>3.5,'Legions advance through deployment into combat')
	app.sound.stop()
	print('%d regional terrain checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)

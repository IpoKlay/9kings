extends SceneTree
var app
const OUT='res://../output/legions-v1/'
func _init():call_deferred('run')
func capture(name):
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUT+name+'.png')
func run():
	root.size=Vector2i(1280,720)
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-legions-preview.cfg'
	root.add_child(app);current_scene=app
	app.sound.enabled=false;app.set_process(false)
	app.restart_expedition(1);app.expedition_map.settle_entry()
	app.travel_to(app.expedition.destinations()[0])
	app.campaign.g.buildings=[]
	for row in 3:
		for col in 3:
			app.campaign.g.buildings.append({'id':row*4+col+1,'cell':row*4+col,'type':['legion','archer','cavalry'][col],'level':row+1})
	app.campaign.g.buildings.append({'id':4,'cell':3,'type':'siege','level':1})
	app.campaign.g.buildings.append({'id':8,'cell':7,'type':'medic','level':2})
	app.campaign.g.buildings.append({'id':12,'cell':11,'type':'siege','level':3})
	app.campaign.g.nextId=13
	app.campaign.g.offerYear=app.campaign.g.round
	app.campaign.g.offered=['legion','medic','testudo']
	app.render_ui()
	await create_timer(.6).timeout
	await capture('01-deployment-and-cards')
	app.campaign.skip();app.campaign.g.orders.testudo=true;app.campaign.g.upgrades.testudo=2
	app.expedition.finish_supply();app.render_ui()
	await capture('02-march-start')
	for frame in 80:
		for step in 3:
			app.campaign.step(1.0/60)
			app.world.tick(1.0/60)
			app.world.events(app.campaign.g.battle.events)
		await capture('frames/march-%03d'%frame)
		if frame==31:await capture('03-march-middle')
		if frame==68:await capture('04-battle-line')
	# Compare all six facilities on the actual native terrain.
	app.campaign.g.battle=null;app.campaign.g.phase='reward';app.campaign.g.buildings=[]
	for row in 3:
		for col in 2:
			app.campaign.g.buildings.append({'id':row*4+col+1,'cell':row*4+col,'type':['siege','medic'][col],'level':row+1})
	app.campaign.g.offered=['siege','medic','cavalry'];app.render_ui()
	await create_timer(.5).timeout
	await capture('05-facilities')
	app.language='en';app.campaign.g.upgrades={'fireArrows':2,'testudo':2,'volley':2}
	app.campaign.g.offered=['fireArrows','testudo','volley'];app.render_ui()
	await create_timer(.5).timeout
	await capture('06-rank-three-cards')
	app.sound.stop();quit()

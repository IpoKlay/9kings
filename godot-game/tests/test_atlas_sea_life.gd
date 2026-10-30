extends SceneTree
var checks=0
var failures=0
var app
const EVIDENCE='/Users/ip/Documents/ChatGPT/9kings/output/atlas-ship-kraken/'

func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)

func capture(name: String):
	if DisplayServer.get_name()=='headless': return
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(EVIDENCE+name+'.png')

func run():
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-atlas-sea-life.cfg'
	app.main_menu=false
	root.add_child(app)
	app.set_process(false)
	app.sound.enabled=false
	app.language='zh';app.world.language='zh'
	app.campaign.reset(23);app.expedition.reset();app.render_ui()
	var map=app.expedition_map
	map.settle_entry()
	var atlas=map.atlas
	atlas.set_process(false)
	var life=atlas.sea_life
	var initial_campaign=JSON.stringify(app.campaign.g)
	var initial_expedition=JSON.stringify(app.expedition.state)
	check(life.ships.size()==3,'Three original pack ships on the production atlas')
	check(life.show_behind_parent and life is Node2D,'Decorations stay below route/UI drawing without GUI input')
	var safe=true
	for y in range(-128,129,16):
		for x in range(-128,129,16):
			if not map.sea.is_water(life.preset.kraken_position+Vector2(x,y)): safe=false
	check(safe,'Entire octopus canvas is in open water')
	for i in life.ships.size():
		var ship=life.ships[i]
		var period=ship.curve.get_baked_length()*2.0/ship.speed
		safe=true
		for sample in 201:
			var pose=life.ship_pose(i,period*sample/200.0)
			for offset in [Vector2.ZERO,Vector2(-64,-64),Vector2(64,-64),Vector2(-64,64),Vector2(64,64)]:
				if not map.sea.is_water(pose.position+offset): safe=false
		check(safe,'Ship hull stays in water throughout both directions: '+str(i))
		check(ship.frames.get_animation_names().size()==8,'Eight authored directions: '+str(i))
		check(ship.frames.get_animation_speed('East')==5.0,'Original 5 fps frames: '+str(i))
		check(life.ship_pose(i,0).position!=life.ship_pose(i,2).position,'Ship sails: '+str(i))
		var end_time=(1.0-ship.phase)*ship.curve.get_baked_length()/ship.speed
		check(life.ship_pose(i,end_time-.01).position.distance_to(life.ship_pose(i,end_time+.01).position)<4,'No teleport at turnaround: '+str(i))
	atlas.overview()
	check(life.position==atlas.sea_surface.position and life.scale==Vector2.ONE*atlas.zoom,'Overview shares the terrain transform')
	await capture('original-map-overview')
	atlas.zoom=.76;atlas.center=Vector2(1820,1110);atlas.layout()
	check(life.position==atlas.sea_surface.position and life.scale==Vector2.ONE*atlas.zoom,'Zoom shares the terrain transform')
	await capture('original-map-west')
	for i in 20: atlas._process(.1)
	check(life.clock>0,'Decorations use the active map clock')
	await capture('original-map-west-moving')
	var old_clock=life.clock
	map.hide();atlas._process(.1)
	check(life.clock==old_clock,'Hidden map freezes decorative animation')
	map.show();app.open_dialog('settings');atlas._process(.1)
	check(life.clock==old_clock,'Settings dialog freezes decorative animation')
	app.close_dialog()
	map.render();atlas=map.atlas;atlas.set_process(false);life=atlas.sea_life
	check(life.clock==old_clock,'Rebuilding map UI retains the ship timeline')
	life.update_time(20,true)
	check(life.clock==0,'Reduced motion provides a static pose')
	life.update_time(map.sea.clock)
	check(JSON.stringify(app.campaign.g)==initial_campaign,'Decorations do not change combat state')
	check(JSON.stringify(app.expedition.state)==initial_expedition,'Decorations do not change expedition progress')
	app.sound.stop()
	print('%d atlas sea life checks, %d failures'%[checks,failures])
	app.queue_free();await process_frame
	quit(1 if failures else 0)

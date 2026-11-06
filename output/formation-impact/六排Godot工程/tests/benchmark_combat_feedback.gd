extends SceneTree
## Native, uncapped render benchmark. The dense fixture deliberately sustains impacts.
const OUT='res://../output/combat-feel-v1/'
const Campaign=preload('res://scripts/campaign.gd')
func _init():call_deferred('run')
func run():
	if DisplayServer.get_name()=='headless':printerr('Native renderer required');quit(1);return
	root.size=Vector2i(960,540)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	var samples=[]
	for label in ['before','after','after','before']:
		var game=Campaign.new(23)
		game.g.buildings=[]
		for i in 12:game.g.buildings.append({'id':i+1,'type':'legion','cell':i,'level':3})
		game.g.round=30;game.skip();game.start()
		var source='res://scripts/battlefield.gd' if label=='after' else ProjectSettings.globalize_path(OUT+'before/scripts/battlefield.gd')
		var field=load(source).new()
		if label=='before':field.feedback=load(ProjectSettings.globalize_path(OUT+'before/data/presentation/feedback.tres')).values.duplicate(true)
		field.game=game;field.scale=Vector2(.5,.5);root.add_child(field);field.refresh()
		var soldier_count=0
		for u in game.g.battle.units:soldier_count+=int(u.get('soldierCount',1 if u.type=='siege' else 5 if u.type=='cavalry' else 3 if u.type=='medic' else 9))
		var times=[];var draws=[]
		var started=Time.get_ticks_usec()
		for frame in 600:
			field.tick(1.0/60);field.tick_environment(1.0/60)
			var events=[]
			# Frozen health/positions ensure both passes draw precisely the same army.
			# Twenty sustained hit events each 6 frames (200 hits/second), plus siege.
			if frame%6==0:
				for i in mini(20,game.g.battle.units.size()):
					var u=game.g.battle.units[i]
					events.append({'kind':'attack','id':u.id,'x':u.x,'y':u.y,'side':u.side})
					events.append({'kind':'hit','id':u.id,'x':u.x,'y':u.y,'side':u.side,'damage':14,'absorbed':6 if i%3==0 else 0,'broken':i%7==0})
			if frame%30==0:events.append({'kind':'blast','x':500,'y':0,'side':'ally'})
			field.events(events)
			await process_frame
			RenderingServer.force_draw()
			var now=Time.get_ticks_usec()
			if frame>=120:times.append(float(now-started)/1000);draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			started=now
			if frame==300 and label=='after':root.get_texture().get_image().save_png(OUT+'dense-native-960x540.png')
		times.sort();draws.sort()
		var total=0.0
		for v in times:total+=v
		samples.append({'label':label,'samples':times.size(),'soldiers':soldier_count,'squads':game.g.battle.units.size(),'mean_frame_ms':total/times.size(),'median_frame_ms':times[times.size()/2],'p95_frame_ms':times[int(times.size()*.95)],'median_draw_calls':draws[draws.size()/2]})
		field.queue_free();await process_frame
	var file=FileAccess.open(OUT+'performance.json',FileAccess.WRITE)
	file.store_string(JSON.stringify({'renderer':RenderingServer.get_video_adapter_name(),'resolution':'960x540','mode':'uncapped vsync off; force_draw + process_frame; synthetic dense fixture; excludes full UI','samples':samples},'\t'))
	print(JSON.stringify(samples))
	quit()

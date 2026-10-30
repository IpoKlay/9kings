extends SceneTree
## Deterministic native rendering of the existing battle simulation, before/after presentation edits.
const Campaign=preload('res://scripts/campaign.gd')
var field
var view: SubViewport
func _init():call_deferred('run')
func run():
	var label='after' if '--after' in OS.get_cmdline_user_args() else 'before'
	var out='res://../output/combat-feel-v1/'+label
	DirAccess.make_dir_recursive_absolute(out)
	var host=Window.new();root.add_child(host)
	view=SubViewport.new();view.size=Vector2i(960,540)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	host.add_child(view)
	var game=Campaign.new(23);game.skip();game.start()
	var source='res://scripts/battlefield.gd' if label=='after' else ProjectSettings.globalize_path('res://../output/combat-feel-v1/before/scripts/battlefield.gd')
	field=load(source).new()
	if label=='before':field.feedback=load(ProjectSettings.globalize_path('res://../output/combat-feel-v1/before/data/presentation/feedback.tres')).values.duplicate(true)
	field.game=game;field.scale=Vector2(.5,.5);view.add_child(field)
	field.refresh()
	var events=[]
	var start_time=-1.0
	var frames=0
	var image: Image
	for step in 3600:
		field.tick(1.0/60.0);field.tick_environment(1.0/60.0)
		if game.g.phase=='battle':
			game.step(1.0/60.0);field.events(game.g.battle.events)
			for e in game.g.battle.events:
				if e.kind in ['hit','blast','death']:
					events.append({'time':game.g.battle.time,'event':e.duplicate(true)})
					if start_time<0:start_time=game.g.battle.time
		if start_time<0:continue
		if step%2!=0:continue
		await process_frame
		RenderingServer.force_draw()
		image=view.get_texture().get_image()
		assert(image.get_size()==Vector2i(960,540))
		assert(image.save_png(out+'/frame-%03d.png'%frames)==OK)
		frames+=1
		if frames>=180:break
	assert(frames==180,'Battle must produce impacts for comparison')
	var f=FileAccess.open(out+'/events.json',FileAccess.WRITE)
	f.store_string(JSON.stringify({'frames':frames,'fps':30,'first_impact_time':start_time,'events':events,'final_battle':game.g.battle},'\t'))
	print('Native combat comparison captured: '+label+', 180 frames; first impact at '+str(start_time))
	quit()

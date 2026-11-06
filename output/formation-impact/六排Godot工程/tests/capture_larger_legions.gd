extends SceneTree
const Campaign=preload('res://scripts/campaign.gd')
const OUT='res://../output/larger-legions/'
func _init():call_deferred('run')
func run():
	if DisplayServer.get_name()=='headless':printerr('Native renderer required');quit(1);return
	root.size=Vector2i(960,540)
	var view=SubViewport.new();view.size=Vector2i(960,540)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(view)
	var states={}
	for label in ['before','after']:
		var source='res://scripts/battlefield.gd' if label=='after' else ProjectSettings.globalize_path(OUT+'before/scripts/battlefield.gd')
		for example in ['deployment','battle','dense']:
			var game=Campaign.new(23);game.skip()
			if example!='battle':
				game.g.buildings=[]
				for i in 12:game.g.buildings.append({'id':i+1,'cell':i,'type':['legion','archer','cavalry','spear'][i%4],'level':3 if example=='dense' else 1+int(i/4.0)})
				game.g.nextId=13
			var field=load(source).new();field.game=game;field.scale=Vector2(.5,.5)
			view.add_child(field);field.refresh()
			for cell in 12:
				var center=field.center(cell)
				assert(field.cell_at(field.project(center.x,center.y))==cell,'Deployment tile selection stays aligned')
			if example!='deployment':
				game.start()
				for step in 420:
					field.tick(1.0/60);game.step(1.0/60)
					if game.g.battle!=null:field.events(game.g.battle.events)
			if label=='before':states[example]=game.g.duplicate(true)
			else:assert(game.g==states[example],'Size changes must not change simulation outcomes')
			for frame in 4:await process_frame;RenderingServer.force_draw()
			view.get_texture().get_image().save_png(OUT+label+'-'+example+'.png')
			field.queue_free();await process_frame
	print('Native size comparison captured; all tile centers and same-seed states match.')
	quit()

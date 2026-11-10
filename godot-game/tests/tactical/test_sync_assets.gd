extends SceneTree
var failures=0
var checks=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	var atlas=preload('res://scripts/tactical/unit_atlas.gd').new()
	var manifest=JSON.parse_string(FileAccess.get_file_as_string('res://assets/rts-armies/atlas/units.json'))
	for id in manifest.sheets:
		var path='res://assets/rts-armies/'+id+'.png'
		check(FileAccess.get_sha256(path)==manifest.sheets[id].source_sha256,'Source checksum '+id)
		var original=load(path).get_image()
		var packed=atlas.sheet(id).get_image()
		var entry=manifest.sheets[id];var box=entry.region
		var source=Image.new();source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		var page=Image.new();page.load_png_from_buffer(FileAccess.get_file_as_bytes('res://assets/rts-armies/atlas/'+entry.page))
		check(source.get_data()==page.get_region(Rect2i(box[0],box[1],box[2],box[3])).get_data(),'Exact source PNG '+id)
		var same=original.get_size()==packed.get_size()
		# Godot's alpha-border fix may change invisible RGB at packed sheet edges.
		if original.get_data()!=packed.get_data():
			for y in original.get_height():
				for x in original.get_width():
					var a=original.get_pixel(x,y);var b=packed.get_pixel(x,y)
					if a.a!=b.a or (a.a>0. and a!=b):same=false
		check(same,'Imported visible pixels and alpha '+id)
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-sync-assets.cfg';root.add_child(app);app.sound.enabled=false
	var t=load('res://scenes/tactical_trial.tscn').instantiate();t.rules=t.WhiteboardBattle.new(false);t.app=app;root.add_child(t);app.hide();t.set_process(false)
	check(t.field.pass_layout.get_node('Ground').texture.resource_path=='res://assets/environments/iberia-grass-ground.png','Whiteboard uses committed grass')
	t.combined_button.pressed.emit();t.start_button.pressed.emit()
	var u=t.rules.units[0]
	for slot in u.soldiers.size():t.rules.Charges.detach(t.rules,u,slot)
	u.soldiers[0].personal_order='move';u.soldiers[1].personal_order='hold'
	check(t.displayed_order(u)=='mixed','Split orders are described from living soldiers')
	u.soldiers[0].charge_run={}
	check(t.displayed_order(u)=='charge','Charging soldier takes display priority')
	u.soldiers[0].hp=0
	check(t.displayed_order(u)!='charge','Dead soldier does not show charging')
	var button=t.start_button;var old=button.position;button.position+=Vector2(-31,-12);t.refresh()
	check(button.position==old+Vector2(-31,-12),'Refresh preserves authored button position')
	button.position=old
	t.retry()
	check(t.rules.phase=='deploy' and t.field.pass_layout.has_node('Ground'),'Retry keeps grass and resets battle')
	var cache=weakref(t.field.unit_atlas)
	t.queue_free();app.queue_free();atlas=null
	await process_frame;await process_frame;await create_timer(.15).timeout
	check(cache.get_ref()==null,'Leaving battle releases its atlas owner')
	print('Sync assets: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)

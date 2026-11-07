extends SceneTree
func _initialize():call_deferred('run')
func run():
	var out='res://../output/sword-banner-reference/corpse-motion/variants/'
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-corpse-variants.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false;t.field.clean_capture=true
	var r=t.rules;r.units.clear();r.next_id=0
	for kind in r.config.types:
		r.config.types[kind].files=1;r.config.types[kind].hp=r.config.types[kind].get('individual',{}).get('hp',100.);r.contact_profiles[kind]=r.Contact.profile(kind,r.config.types[kind],true)
	var entries=[['legion',''],['cavalry',''],['archer','skeleton_archer'],['cavalry','death_rider'],['legion','fell_hound'],['legion','wraith'],['guard','dragon'],['siege',''],['guard','goblin_troll']]
	var labels=[]
	for i in entries.size():
		var kind:String=entries[i][0];var variant:String=entries[i][1]
		var stats:Dictionary=r.config.types[kind] if variant=='' else r.config.unit_variants[variant]
		stats.files=1;stats.hp=float(stats.get('individual',{}).get('hp',100.))
		r.spawn(kind,'ally',Vector2(650+(i%3)*350,750+(i/3)*300),variant)
		var u:Dictionary=r.units.back();u.heading=Vector2.RIGHT.rotated((i%3)*PI/4);u.formation_heading=u.heading;u.order='hold';r.Charges.detach(r,u,0);u.soldiers[0].position=u.pos;u.soldiers[0].personal_order='hold';u.soldiers[0].heading=u.heading
		var label=Label.new();label.text=stats.get('name_en',kind);label.position=r.projection*u.pos+Vector2(-90,60);label.add_theme_font_size_override('font_size',20);t.field.add_child(label);labels.append(label)
	r.spawn('legion','ally',Vector2(100,1900));r.spawn('legion','enemy',Vector2(1950,100))
	for u in r.units:
		u.order='hold'
		for a in u.soldiers:a.cooldown=999.
	t.set_camera(r.projection*Vector2(1000,1100)-Vector2(960,540)/t.zoom);t.refresh();t.start_button.pressed.emit();r.enemy_director.active=false
	var seen=[]
	for frame in 300:
		if frame==60:
			for i in entries.size():r.hurt(r.units[i],100000.)
		t._process(1./60)
		for body in r.casualties:
			if body.unit_id<9 and body.unit_id not in seen:seen.append(body.unit_id)
		RenderingServer.force_draw();await process_frame
		if frame in [40,65,90,150,245]:
			RenderingServer.force_draw();root.get_texture().get_image().save_png(out+'frame-%04d.png'%frame)
	var remaining=r.casualties.size();t.retry();var clean=t.rules.casualties.is_empty()
	FileAccess.open(out+'report.json',FileAccess.WRITE).store_string(JSON.stringify({'fixture':'Normal menu; nine one-person reference types killed by controlled direct damage at1s, stationary, default zoom, normal speed. Art/lifecycle diagnostic, not a combat comparison.','entries':entries,'seen':seen,'expired':remaining==0,'retry_clean':clean,'failures':0 if seen.size()==9 and remaining==0 and clean else 1},'\t'))
	for label in labels:label.queue_free()
	t.closed.emit();app.queue_free();await process_frame;quit(0 if seen.size()==9 and remaining==0 and clean else 1)

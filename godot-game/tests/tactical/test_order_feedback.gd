extends SceneTree
const OUT='res://../output/pass-report/'
const DT=1./60
var failed=0
var t
var main
var evidence: FileAccess
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:
		failed+=1
		push_error(note)
func click(pos: Vector2):
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=pos
		e.global_position=pos
		e.button_index=MOUSE_BUTTON_LEFT
		e.pressed=down
		root.push_input(e,true)
func screen(p: Vector2) -> Vector2:return (t.field.project(p)-t.camera_offset)*t.zoom
func snap(name: String):
	t.refresh()
	t.field.queue_redraw()
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	var img=root.get_texture().get_image()
	img.save_png(OUT+'%s-%s-%d.png'%[main.language,name,img.get_width()])
	for i in range(1,t.roster.size()):
		if t.roster[i].visible:
			check(t.roster[i-1].get_rect().end.x<=t.roster[i].position.x,'Adjacent roster tabs fit')
	var panel=t.recap if t.result.visible else t.order_strip
	var rect: Rect2=panel.get_rect()
	check(rect.position.y>=830 and rect.end.x<=1920 and rect.end.y<=1080,'Readout inside lower HUD')
	check(panel.get_theme_font('font').get_string_size(panel.text,HORIZONTAL_ALIGNMENT_LEFT,-1,panel.get_theme_font_size('font_size')).x+24<rect.size.x,'Text fits strip: '+panel.text)
	evidence.store_line(JSON.stringify({'language':main.language,'case':name,'size':str(img.get_size()),'command':t.order_strip.text,'result':t.result.text,'summary':t.recap.text,'journal':t.rules.journal}))
func scenario(lang: String):
	main.language=lang
	click(main.menu_view.get_node('%TacticalTrial').get_global_rect().get_center())
	await process_frame
	t=root.get_child(-1)
	click(t.defender_button.get_global_rect().get_center())
	await process_frame
	click(t.start_button.get_global_rect().get_center())
	await process_frame
	t.paused=true
	var r=t.rules
	var guard=r.alive('ally')[0]
	for u in r.units:u.order='hold'
	var enemy=r.alive('enemy')[0]
	guard.pos=r.terrain.inverse*Vector2(600,610)
	enemy.pos=r.terrain.inverse*Vector2(1090,610)
	click(screen(guard.pos)-Vector2(0,35)*t.zoom)
	click(screen(r.terrain.inverse*Vector2(1450,610)))
	await snap('paused')
	check(guard.order=='move' and t.order_strip.text.contains('暂停' if lang=='zh' else 'Paused'),'Paused order visible')
	t.paused=false
	for i in 700:
		await process_frame
		if guard.obstruction=='contact':break
	await snap('intercepted')
	check(t.order_strip.text.contains('受阻' if lang=='zh' else 'Blocked') and guard.order=='attack','Intercepted march displayed')
	t.paused=true
	click(screen(guard.pos)-Vector2(0,35)*t.zoom)
	click(screen(r.flag_center))
	t.paused=false
	await snap('returning')
	check(t.order_strip.text.contains('回防军旗' if lang=='zh' else 'Returning to flag'),'Real return order visible')
	t.paused=true
	var general=r.alive('ally').filter(func(u):return u.general)[0]
	t.squad_ids=[general.id]
	general.morale=.01
	r.hurt(general,1)
	r.hurt(general,1)
	t.refresh()
	check(t.order_strip.text.contains('溃退' if lang=='zh' else 'Routing') and t.rout_alerts.size()==1,'Routed commander stays inspectable; one warning')
	enemy.pos=r.flag_center
	for u in r.alive('ally'):u.pos=Vector2(760,480)
	for i in 120:r.step(DT)
	guard.pos=r.flag_center
	for i in 30:r.step(DT)
	guard.pos=Vector2(760,480)
	for i in 605:r.step(DT)
	await snap('flag-lost')
	var e: Dictionary=r.key_event()
	check(r.outcome=='flag_lost' and e.kind=='captured' and e.contested and e.seconds==12,'Captured event records interrupted clock')
	check(t.result.text.contains('失守' if lang=='zh' else 'fell') and t.recap.text.contains('累计' if lang=='zh' else 'total'),'Reason and actual recorded episode in recap')
	check(r.journal.filter(func(x):return x.kind=='flag_threat').size()==1,'Contesting and resuming is one flag alert')
	check(r.journal.filter(func(x):return x.kind=='general_rout').size()==1,'Repeated damage causes one rout event')
	click(t.start_button.get_global_rect().get_center())
	await process_frame
	check(t.rules.journal.is_empty() and not t.recap.visible and t.rout_alerts.is_empty(),'New battle clears history and UI')
	t.closed.emit()
	await process_frame
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	evidence=FileAccess.open(OUT+'report-%d.jsonl'%root.size.x,FileAccess.WRITE)
	main=load('res://scenes/main.tscn').instantiate()
	main.run_path_override='user://order-feedback-test-absent.cfg'
	root.add_child(main)
	await process_frame
	for lang in ['zh','en']:await scenario(lang)
	evidence.close()
	main.queue_free()
	await process_frame
	print('ORDER FEEDBACK failures: ',failed)
	quit(1 if failed else 0)

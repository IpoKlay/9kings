extends SceneTree
## Run Godot editor binary with --main-pack <exported PCK> --script <absolute file> -- <absolute output directory>.
var checks=0
var failures=0
var out=''
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func shot(name: String):
	if DisplayServer.get_name()=='headless':return
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(out+'/'+name+'.png')
func run():
	var args=OS.get_cmdline_user_args()
	out=args[0] if not args.is_empty() else OS.get_user_data_dir()+'/checkpoint-check'
	DirAccess.make_dir_recursive_absolute(out)
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path=out+'/test-settings.cfg';root.add_child(app)
	AudioServer.set_bus_mute(0,true);await process_frame;shot('menu')
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	for key in ['corpse_parts','corpse_rigs','projectile_anchors']:
		check(FileAccess.file_exists('res://data/presentation/'+key+'.json'),'Pack contains '+key)
	for kind in t.field.corpse_parts:
		for side in ['ally','enemy']:
			var tex=t.field.tex('rts-corpses/'+kind+'_'+side)
			check(tex!=null and tex.get_height()==1024,'Pack loads corpse atlas '+kind+' '+side)
	t.combined_button.pressed.emit();await process_frame;shot('deployment')
	t.start_button.pressed.emit();var r=t.rules
	check(r.units.size()==14 and r.phase=='battle','Normal menu starts fourteen seven-arm regiments')
	r.command(r.alive('ally').map(func(u):return u.id),'auto',Vector2.ZERO)
	t.paused=true;var frozen=r.elapsed;t._process(1.);check(r.elapsed==frozen,'Pause freezes export');t.paused=false
	t.slow=true
	for i in 120:t._process(1./60.)
	check(is_equal_approx(r.elapsed,1.),'Half speed preserves exported simulation clock');t.slow=false
	var saw_arrow=false;var saw_stone=false;var saw_body=false
	for frame in 60*179:
		t._process(1./60.)
		saw_arrow=saw_arrow or not r.volleys.is_empty();saw_stone=saw_stone or not r.stones.is_empty();saw_body=saw_body or not r.casualties.is_empty()
		await process_frame
		if frame in [240,600,1200]:shot('battle-'+str(frame))
		if r.phase!='battle':break
	check(r.phase=='victory' and is_equal_approx(r.elapsed,37.933333333333),'Export naturally reproduces default battle result')
	check(r.strength('ally')==17. and saw_arrow and saw_stone and saw_body,'Natural battle contains arrows, stones and casualties')
	shot('victory');var finish=r.elapsed
	t.start_button.pressed.emit();check(t.rules.phase=='deploy' and t.rules.casualties.is_empty() and t.rules.stones.is_empty() and t.rules.volleys.is_empty(),'Result button resets combat state')
	t.combined_button.pressed.emit();t.start_button.pressed.emit();r=t.rules
	for u in r.alive('ally'):r.hurt(u,100000.)
	for kind in r.reserve:r.reserve[kind]=0
	for i in 10:t._process(1./60.)
	check(r.phase=='defeat','Forced lethal fixture reaches defeat UI; not a natural-loss balance test')
	shot('defeat');t.start_button.pressed.emit();check(t.rules.phase=='deploy','Defeat button retries once')
	t.siege_button.pressed.emit();r=t.rules
	check(r.structures.size()==7,'Export includes seven authored siege walls')
	t.start_button.pressed.emit()
	var engine=r.alive('ally').filter(func(u):return u.kind=='siege')[0]
	var engines=[]
	for slot in engine.soldiers.size():engines.append(Vector2i(engine.id,slot))
	check(r.Structures.order(r,engines,r.structures[3]),'Export accepts wall bombardment')
	for i in 600:t._process(1./60.)
	check(r.structures[3].hits==r.structures[3].limit,'Fifth hit opens exported wall')
	var report={'checks':checks,'failures':failures,'normal_battle_seconds':finish,'rendered':DisplayServer.get_name()!='headless','scope':'Exported PCK loaded by Godot 4.7.2 editor binary; real menu callbacks, natural seven-arm victory, pause/half speed, retry, explicit forced defeat fixture and siege bombardment. Not manual mouse testing or Windows runtime validation.'}
	FileAccess.open(out+'/export-validation.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	t.closed.emit();app.queue_free();await process_frame
	print('Checkpoint export: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)

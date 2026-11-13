extends SceneTree
## Run menu-close, battle-close, or release. No --quit-after: exercise actual shutdown.
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	var args=OS.get_cmdline_user_args()
	var mode=args[0] if not args.is_empty() else 'release'
	for iteration in (3 if mode=='release' else 1):
		var app=load('res://scenes/main.tscn').instantiate()
		app.settings_path='/tmp/eagle-audio-shutdown.cfg'
		root.add_child(app)
		check(app.music.players.any(func(p):return p.playing),'Menu music really starts')
		if mode!='menu-close':
			await create_timer(.1).timeout
			app.menu_view.get_node('%TacticalTrial').pressed.emit()
			check(app.active_trial!=null and app.music.requested_track=='battle','Normal RTS entry switches to battle music')
			check(app.music.players.all(func(p):return p.playing),'Both crossfade voices are active at shutdown')
		var playbacks: Array[WeakRef]=[]
		for p in app.music.players:
			if p.has_stream_playback():playbacks.append(weakref(p.get_stream_playback()))
		if mode in ['menu-close','battle-close']:
			print('WINDOW CLOSE DURING AUDIO: ',mode,' checks=',checks,' failures=',failures)
			if failures:await app.prepare_shutdown();app.queue_free();quit(1);return
			root.close_requested.emit()
			root.close_requested.emit() # Duplicate OS close requests must not bypass draining.
			return
		await app.prepare_shutdown()
		check(playbacks.all(func(p):return p.get_ref()==null),'Mixer releases playback references before scene deletion')
		check(app.music.players.all(func(p):return not p.playing and p.stream==null),'Both decks stopped and detached')
		app.music.play_track('menu')
		check(app.music.players.all(func(p):return not p.playing),'Late scene-close callback cannot restart audio')
		if is_instance_valid(app.active_trial):app.active_trial.closed.emit()
		app.queue_free()
		await process_frame
	print('AUDIO SHUTDOWN CHECKS=',checks,' FAILURES=',failures)
	quit(1 if failures else 0)

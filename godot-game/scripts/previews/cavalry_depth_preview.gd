extends Control
## Runs the real trial loop, with a separate authored deployment and existing grass.
const Rules=preload('res://scripts/previews/cavalry_depth_rules.gd')
const Feedback=preload('res://scripts/previews/impact_feedback.gd')
@export var charge_speed=360.0
@export var follow_through=200.0
@export var unbraced_hit_drag=0.08
@export var exit_orders=true
@export var view_zoom=1.0
@export var feedback_enabled=true
@export_range(0.,1.,.1) var flash_strength=1.0
@export_range(0.,3.,.25) var local_shake=2.0
@export_range(0.,3.,1.) var camera_shake=2.0
@export_range(0,6,1) var hit_hold_frames=5
var feedback=Feedback.new()
var trial
var app
var clock=0.
var launched=false
var finished=false
var frame_times: Array=[]
var wall_start=0
var previous_tick=0
var output=""
var snapshots={}
var capture_stills=true
var recording=false
var capture_can_step=true
var recorded_steps=0

func _ready():
	Engine.max_fps=60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var args=OS.get_cmdline_user_args()
	var mode=args[0] if args.size()>0 else 'flank'
	output=args[1] if args.size()>1 else ''
	recording='record' in args
	if recording:RenderingServer.frame_post_draw.connect(capture_drawn)
	capture_stills=not 'perf' in args
	if 'no-feedback' in args:feedback_enabled=false
	if 'no-camera' in args:camera_shake=0.
	if 'baseline' in args:
		charge_speed=240.;follow_through=140.;unbraced_hit_drag=.12;exit_orders=false
	if 'close' in args:view_zoom=4./3.
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-cavalry-depth.cfg';add_child(app);app.hide()
	app.sound.enabled=false
	Engine.max_fps=60
	Engine.time_scale=1.
	get_window().title='Cavalry Depth Preview — 64 soldiers'
	if not output.is_empty():get_window().size=Vector2i(1280,720)
	trial=load('res://scenes/tactical_trial.tscn').instantiate()
	trial.rules=Rules.new(false)
	trial.rules.config.individual_charge.speed=charge_speed
	trial.rules.config.individual_charge.follow_through=follow_through
	trial.rules.config.individual_charge.slow_per_hit=unbraced_hit_drag
	trial.rules.exit_orders=exit_orders
	trial.rules.setup(mode);trial.app=app
	add_child(trial);move_child(trial,0)
	feedback.prepare(trial.field.regiments,trial.rules.units)
	feedback.flash_strength=flash_strength;feedback.local_shake=local_shake;feedback.hold_frames=hit_hold_frames
	trial.field.impact_feedback=feedback
	feedback.enabled=feedback_enabled
	if recording:trial.set_process(false)
	trial.field.clean_capture=true;trial.get_node('BattleHUD').hide()
	trial.set_process_input(false);trial.set_process_unhandled_input(false)
	trial.field.pass_layout.hide()
	var ground=Sprite2D.new()
	ground.texture=preload('res://assets/environments/iberia-grass-ground.png')
	ground.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	ground.texture_repeat=CanvasItem.TEXTURE_REPEAT_MIRROR
	ground.centered=false;ground.position=Vector2(-200,-200)
	ground.region_enabled=true;ground.region_rect=Rect2(0,0,3600,3600);ground.z_index=-3
	trial.field.add_child(ground)
	trial.zoom=view_zoom
	trial.set_camera(Vector2(1490,1670 if view_zoom>1. else 1740)-Vector2(960,540)/view_zoom)
	$Title.text='24 骑 × 40 步兵 · 侧翼冲阵' if mode=='flank' else '同兵力对照 · '+('坚守长矛' if mode=='pikes' else '正面盾墙')
	$Restart.pressed.connect(func():get_tree().reload_current_scene())
	$Pause.pressed.connect(func():trial.paused=not trial.paused)
	$Feedback.pressed.connect(func():
		feedback_enabled=not feedback_enabled;feedback.enabled=feedback_enabled
		update_feedback_controls())
	$CameraShake.pressed.connect(func():
		camera_shake=0. if camera_shake>0. else 2.
		update_feedback_controls())
	update_feedback_controls()
	wall_start=Time.get_ticks_usec()
	previous_tick=wall_start

func _process(delta: float):
	if trial==null or finished or trial.paused:return
	# One normal-speed simulation step per exported 60fps frame. Live runs keep
	# the regular engine loop and are measured separately.
	if recording:
		if not capture_can_step:return
		capture_can_step=false
		recorded_steps+=1
		delta=1./60.
	var now=Time.get_ticks_usec()
	var measured_ms=(now-previous_tick)/1000.
	previous_tick=now
	clock+=delta
	if clock>.5 and not output.is_empty():frame_times.append(measured_ms)
	if clock>=1.2 and not launched:
		launched=true
		var accepted=trial.rules.launch()
		assert(accepted)
	if recording:trial._process(delta)
	trial.field.position=Feedback.camera_offset(trial.rules.elapsed-trial.rules.feedback_shock_time,camera_shake if feedback_enabled else 0.)
	if not output.is_empty() and capture_stills and DisplayServer.get_name()!='headless':
		for time in [1,3,4,5,6,8,11]:
			if clock>=time and not snapshots.has(time):
				snapshots[time]=true;save_frame.call_deferred(time)
	if clock>=12. and not output.is_empty():
		finished=true
		save_report()
		finish_capture.call_deferred()

func update_feedback_controls():
	$Feedback.text='打击反馈：开' if feedback_enabled else '打击反馈：关'
	$CameraShake.text='镜头震动：开' if camera_shake>0. else '镜头震动：关'
	if not feedback_enabled or camera_shake<=0.:trial.field.position=Vector2.ZERO
	trial.field.queue_redraw()

func capture_drawn():
	capture_can_step=true

func finish_capture():
	trial.queue_free();app.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(.15).timeout
	get_tree().quit()

func save_frame(time: int):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output+'/frame-%02d.png'%time)

func save_report():
	var r=trial.rules
	var actors=[]
	for u in r.units:
		for slot in u.soldiers.size():
			var a=u.soldiers[slot]
			actors.append({'id':[u.id,slot],'hp':a.hp,'position':a.position,
				'end':a.get('charge_end',{}),'order':a.personal_order,
				'entered_defense':r.entered_defense.has(Vector2i(u.id,slot)),
				'displacement':a.position.distance_to(r.initial_feet[Vector2i(u.id,slot)])})
	frame_times.sort()
	var report={'mode':r.comparison,'people':64,'sim_seconds':r.elapsed,'wall_seconds':(Time.get_ticks_usec()-wall_start)/1000000.,
		'frame_mean_ms':frame_times.reduce(func(a,b):return a+b,0.)/maxi(1,frame_times.size()),
		'frame_p95_ms':frame_times[int(frame_times.size()*.95)] if not frame_times.is_empty() else 0,
		'stalls_over_50ms':frame_times.filter(func(v):return v>50.).size(),
		'movie':recording, 'contacts':r.contact_log,'actors':actors,'zoom':trial.zoom,
		'recorded_steps':recorded_steps,
		'feedback':feedback_enabled,'camera_shake':camera_shake,'flash_texture_bytes':feedback.texture_bytes,
		'flashed_sides':feedback.flashed_sides,
		'contact_flash_roles':feedback.contact_flash_roles,
		'still_readbacks':capture_stills,'vsync':DisplayServer.window_get_vsync_mode(),
		'static_memory_bytes':Performance.get_monitor(Performance.MEMORY_STATIC),
		'texture_memory_bytes':Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		'charge_speed':charge_speed,'follow_through':follow_through,'unbraced_hit_drag':unbraced_hit_drag,
		'output_size':get_viewport().get_texture().get_image().get_size()}
	FileAccess.open(output+'/report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))

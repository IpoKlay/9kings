extends 'res://scripts/previews/cavalry_depth_preview.gd'
@export var solo=false
var exported_frame=0
var cues: Array=[]
func _ready():
	charge_speed=240.;follow_through=140.;unbraced_hit_drag=.12;exit_orders=false
	view_zoom=4./3.;camera_shake=7.5;hit_hold_frames=5
	super()
	output=ProjectSettings.globalize_path('res://../output/charge-polish-v5/'+('solo' if solo else 'group'))
	DirAccess.make_dir_recursive_absolute(output+'/frames')
	get_window().size=Vector2i(1280,720)
	capture_stills=false;recording=true;trial.set_process(false)
	RenderingServer.frame_post_draw.connect(capture_drawn)
	RenderingServer.frame_post_draw.connect(export_frame)
	app.sound.enabled=true;app.sound.volume=.5
	trial.sound_cue.connect(func(cue):cues.append(cue))
	if solo:
		var r=trial.rules
		var defender: Vector2i=r.defender_ids[0];var rider: Vector2i=r.rider_ids[0]
		r.defender_ids=[defender];r.rider_ids=[rider]
		for u in r.units:
			for slot in u.soldiers.size():
				var key=Vector2i(u.id,slot);var live=key==defender or key==rider
				u.soldiers[slot].hp=1000. if live else 0.
				u.soldiers[slot].death_state=0 if live else 2
			r.Soldiers.total(u)
		var victim=r.units[defender.x].soldiers[defender.y]
		victim.position=r.impact;victim.wall_slot=r.impact;victim.shield_wall=false;victim.cooldown=999.
		r.units[rider.x].soldiers[rider.y].position=r.impact-r.axis*300.
		for u in r.units:r.Soldiers.update_center(r,u,0.)
		trial.zoom=2.5
		trial.set_camera(r.projection*r.impact-Vector2(840,650)/trial.zoom)
	$Title.text='单骑撞击 · 接触、掀翻、落地' if solo else '群体冲阵 · 24 骑兵 × 40 步兵'
	$Note.text='撞击短音 / 群战声音合并 / 后蹄扬尘与定向碎土'
	for button in ['Restart','Pause','Feedback','CameraShake']:get_node(button).hide()
func _process(dt: float):
	super(dt)
	if clock>=6. and not finished:
		finished=true;save_report()
		FileAccess.open(output+'/audio.json',FileAccess.WRITE).store_string(JSON.stringify(cues))
		finish_capture.call_deferred()
func export_frame():
	if recorded_steps<=exported_frame or not is_instance_valid(trial):return
	var error=get_viewport().get_texture().get_image().save_png(output+'/frames/%05d.png'%exported_frame)
	if error!=OK:push_error('Video frame save failed');get_tree().quit(1)
	exported_frame=recorded_steps

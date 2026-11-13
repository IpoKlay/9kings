extends Node
## Optional read-only observer attached to a normally running trial; never steps the simulation.
const OUT='res://../output/whiteboard-command-loop-2026-11-07/'
var trial
var started=0
var frames=0
var start_seconds=0.
var timings=[]
var captured=[]
var initial={}
func _ready():
	var output_directory_error=DirAccess.make_dir_recursive_absolute(OUT)
	assert(output_directory_error==OK)
	process_priority=1
func capture(label: String):
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT+'live-'+label+'.png')
func _process(dt: float):
	if trial==null:return
	var r=trial.rules
	if started==0:
		if r.phase!='battle':return
		started=Time.get_ticks_usec();start_seconds=r.elapsed;frames=Engine.get_frames_drawn()
		initial={'ally':r.strength('ally'),'enemy':r.strength('enemy'),'regiments':r.units.size(),'zoom':trial.zoom}
		return
	timings.append(dt*1000.)
	for second in [8,20]:
		if r.elapsed>=second and second not in captured:
			captured.append(second);capture.call_deferred(str(second)+'s')
	if r.phase=='battle':return
	var wall=(Time.get_ticks_usec()-started)/1000000.
	timings.sort()
	var report={'phase':r.phase,'initial':initial,'remaining':{'ally':r.strength('ally'),'enemy':r.strength('enemy')},
		'wall_seconds':wall,'simulation_seconds':r.elapsed-start_seconds,'average_render_fps':(Engine.get_frames_drawn()-frames)/wall,
		'p95_frame_ms':timings[mini(timings.size()-1,int(timings.size()*.95))],'normal_process':trial.is_processing(),'slow':trial.slow,
		'scope':'Unmodified main-loop timing in visible editor-launched game; includes screenshot readback and tool input. Not a thousand-unit benchmark.'}
	FileAccess.open(OUT+'live-battle.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	capture.call_deferred('result');set_process(false)

extends SceneTree
const OUT='res://../output/battle-atlas-integration-2026-11-09/'
var app
var t
var results=[]
func _initialize():call_deferred('run')
func shot():
 t.field.queue_redraw()
 for i in 6:
  await process_frame
  RenderingServer.force_draw()
 return t.field.get_viewport().get_texture().get_image()
func compare(label):
 t.field.set_unit_atlas_enabled(false);var before=await shot()
 t.field.set_unit_atlas_enabled(true);var after=await shot()
 var same=before.get_data()==after.get_data()
 if not same:
  t.field.atlas_shadows_enabled=false;var sprites=await shot();sprites.save_png(OUT+label+'-sprites.png');t.field.atlas_shadows_enabled=true
 results.append({'case':label,'identical':same});print('ATLAS ',label,' ',same)
 before.save_png(OUT+label+'-before.png');after.save_png(OUT+label+'-after.png')
func run():
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 seed(20261109)
 root.always_on_top=true
 app=load('res://scenes/main.tscn').instantiate();app.settings_path=OUT+'temp-test.cfg';app.run_path_override=OUT+'temp-test.json';root.add_child(app)
 app.menu_view.get_node('%TacticalTrial').pressed.emit();t=app.active_trial;t.set_process(false);t.combined_button.pressed.emit();t.refresh();AudioServer.set_bus_mute(0,true)
 for z in [1.0,.2375,5./3.]:
  t.zoom=z;t.set_camera(t.camera_offset);await compare('zoom-'+str(z))
 t.reset_camera();t.start_or_hold();t.rules.command(t.rules.alive('ally').map(func(u):return u.id),'auto',Vector2.ZERO)
 for i in 1200:
  t._process(1./60)
  if i in [0,30,60,120,240,480,720,960,1199]:await compare('combat-'+str(i))
 for u in t.rules.units:u.petrified=3.0
 await compare('petrified')
 FileAccess.open(OUT+'world-pixels.json',FileAccess.WRITE).store_string(JSON.stringify(results,'\t'))
 var failed=results.filter(func(r):return not r.identical).size()
 print('WORLD ATLAS ',failed,' failures')
 t.closed.emit();app.queue_free();await process_frame;quit(1 if failed else 0)

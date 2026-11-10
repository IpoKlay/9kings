extends SceneTree
const OUT='res://../output/battle-atlas-integration-2026-11-09/'
class Sheet extends Node2D:
 var texture: Texture2D
 var factor=.615
 var angle=0.0
 func _draw():
  var columns=texture.get_width()/64
  for row in 8:
   for col in columns:
    draw_set_transform(Vector2(35+col*57,45+row*80),angle)
    var dest=Rect2(-Vector2(32,54)*factor,Vector2(64,64)*factor)
    if col%2==0:
     draw_texture_rect_region(texture,dest,Rect2(col*64,row*64,64,64))
    else:
     draw_texture_rect_region(texture,Rect2(dest.position,Vector2(64,32)*factor),Rect2(col*64,row*64,64,32))
     draw_texture_rect_region(texture,Rect2(dest.position+Vector2(0,32)*factor,Vector2(64,32)*factor),Rect2(col*64,row*64+32,64,32))
  draw_set_transform(Vector2.ZERO)
var vp
var sheet
func _initialize():call_deferred('run')
func capture(texture):
 sheet.texture=texture;sheet.queue_redraw()
 for i in 2:
  await process_frame
  RenderingServer.force_draw()
 return vp.get_texture().get_image()
func run():
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 root.always_on_top=true;Engine.max_fps=0
 vp=SubViewport.new();vp.size=Vector2i(1024,768);vp.transparent_bg=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;vp.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST;root.add_child(vp)
 sheet=Sheet.new();vp.add_child(sheet)
 var meta=JSON.parse_string(FileAccess.get_file_as_string('res://assets/rts-armies/atlas/units.json'));var pages={};var failures=[];var count=0
 for name in meta.sheets:
  var item=meta.sheets[name]
  if not pages.has(item.page):pages[item.page]=load('res://assets/rts-armies/atlas/'+item.page)
  var a=AtlasTexture.new();a.atlas=pages[item.page];var r=item.region;a.region=Rect2(r[0],r[1],r[2],r[3]);a.filter_clip=true
  var original=load('res://assets/rts-armies/'+name+'.png')
  for mode in [[.615,0.0],[.93,0.0],[.915,0.0],[.1460625,0.0],[1.025,0.0],[.615,.08]]:
   sheet.factor=mode[0];sheet.angle=mode[1]
   var before=await capture(original);var after=await capture(a);count+=1
   if before.get_data()!=after.get_data():
    failures.append([name,mode]);print('DIFF ',name,' ',mode)
    if failures.size()<=8:before.save_png(OUT+str(failures.size())+'-before.png');after.save_png(OUT+str(failures.size())+'-after.png')
 print('RESULT ',count,' cases ',failures.size(),' differences')
 FileAccess.open(OUT+'all-edges.json',FileAccess.WRITE).store_string(JSON.stringify({'count':count,'differences':failures},'\t'))
 vp.queue_free();await process_frame;quit(1 if not failures.is_empty() else 0)

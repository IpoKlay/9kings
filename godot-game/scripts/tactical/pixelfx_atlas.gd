extends RefCounted

const ROOT = 'res://assets/fx/pixelfx/'
var sheets: Dictionary = {}

func _init():
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ROOT+'source.json'))
	for path in source.effects:
		var id: String=path.get_file()
		var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ROOT+id+'.json'))
		var meta: Dictionary=data.meta.pixelfx
		var regions: Array[Rect2]=[]
		for frame in data.frames:
			var r=frame.frame
			regions.append(Rect2(r.x,r.y,r.w,r.h))
		sheets[id]={'texture':load(ROOT+id+'.png'),'regions':regions,'fps':float(meta.fps),'pivot':Vector2(meta.pivot[0],meta.pivot[1]),'loop':bool(meta.loop)}

func duration(id: String) -> float:
	return sheets[id].regions.size()/sheets[id].fps

func frame_index(id: String, age: float) -> int:
	var index=floori(age*sheets[id].fps+0.00001)
	return index if index>=0 and index<sheets[id].regions.size() else -1

func draw(canvas: CanvasItem, id: String, position: Vector2, age: float, alpha: float=1.0):
	var index=frame_index(id,age)
	if index<0:return
	var sheet: Dictionary=sheets[id]
	var region: Rect2=sheet.regions[index]
	# Field renders at half resolution: 2x here preserves one source pixel per viewport pixel.
	canvas.draw_texture_rect_region(sheet.texture,Rect2(position.snapped(Vector2(2,2))-sheet.pivot*2,region.size*2),region,Color(1,1,1,alpha))

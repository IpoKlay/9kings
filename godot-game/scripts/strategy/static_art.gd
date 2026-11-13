extends RefCounted
## Unmodified static PixelLab artwork for terrain, buildings and unit icons.
const ROOT='res://assets/strategy/pixellab-v2/'
const BUILDINGS={'town':['B01','B02','B03'],'barracks':['B04','B05','B06'],'range':['B07'],'stable':['B08'],'academy':['B09'],'factory':['B10'],'wall':['B11'],'gate':['B12'],'wall_tower':['B13'],'outpost':['B14','B15','B16'],'fortress':['B17','B18','B19'],'house':['B20','B21','B22'],'farm':['B23']}
const UNITS={'villager':['U01'],'engineer':['U02'],'spear':['U03','U04','U05','U06','U07'],'shield':['U08','U09','U10','U11','U12'],'archer':['U13','U14','U15','U16','U17'],'light_cavalry':['U18','U19','U20','U21','U22'],'elite_cavalry':['U23']}
const RESOURCES={'iron':'M04','large_iron':'M04','sheep':'M07','cattle':'M08','deer':'M09','fish':'M10','boar':'M11','farm':'B23'}
const REGIONS={
	"B01": Rect2(31,56,199,140),
	"B02": Rect2(8,46,237,161),
	"B03": Rect2(7,26,234,195),
	"B04": Rect2(5,31,179,133),
	"B05": Rect2(3,24,186,140),
	"B06": Rect2(2,23,187,149),
	"B07": Rect2(6,20,180,120),
	"B08": Rect2(8,8,175,136),
	"B09": Rect2(7,25,177,127),
	"B10": Rect2(9,18,175,145),
	"B11": Rect2(0,11,64,78),
	"B12": Rect2(32,20,134,115),
	"B13": Rect2(0,2,96,146),
	"B14": Rect2(20,6,100,142),
	"B15": Rect2(5,3,109,151),
	"B16": Rect2(10,1,103,154),
	"B17": Rect2(13,38,227,160),
	"B18": Rect2(10,29,235,183),
	"B19": Rect2(12,35,235,175),
	"B20": Rect2(3,5,124,121),
	"B21": Rect2(3,3,122,122),
	"B22": Rect2(2,4,124,121),
	"B23": Rect2(2,18,123,106),
	"M01": Rect2(7,25,115,85),
	"M02": Rect2(0,0,32,32),
	"M03": Rect2(0,1,63,62),
	"M04": Rect2(0,6,64,57),
	"M05": Rect2(1,15,62,32),
	"M06": Rect2(0,15,64,48),
	"M07": Rect2(4,7,22,21),
	"M08": Rect2(2,2,28,28),
	"M09": Rect2(2,0,29,32),
	"M10": Rect2(1,1,14,14),
	"M11": Rect2(1,3,28,28),
	"U01": Rect2(13,6,32,52),
	"U02": Rect2(14,11,27,46),
	"U03": Rect2(29,19,32,54),
	"U04": Rect2(29,19,36,54),
	"U05": Rect2(29,19,36,54),
	"U06": Rect2(29,19,36,54),
	"U07": Rect2(25,18,40,55),
	"U08": Rect2(16,11,26,46),
	"U09": Rect2(16,11,26,46),
	"U10": Rect2(16,11,26,46),
	"U11": Rect2(16,7,26,50),
	"U12": Rect2(14,6,28,51),
	"U13": Rect2(14,10,34,47),
	"U14": Rect2(14,10,35,47),
	"U15": Rect2(14,10,32,47),
	"U16": Rect2(14,7,35,50),
	"U17": Rect2(10,5,37,52),
	"U18": Rect2(24,18,39,61),
	"U19": Rect2(24,18,39,61),
	"U20": Rect2(24,18,39,61),
	"U21": Rect2(24,14,39,65),
	"U22": Rect2(24,14,39,65),
	"U23": Rect2(23,16,40,67)
}
var textures={}
var icons={}
func building_id(kind: String,level: int=1) -> String:
	var choices: Array=BUILDINGS[kind]
	return choices[clampi(level-1,0,choices.size()-1)]
static func unit_id(type: String,level: int=1) -> String:
	var choices: Array=UNITS.get(type,[])
	return '' if choices.is_empty() else choices[clampi(level-1,0,choices.size()-1)]
func texture(id: String) -> Texture2D:
	if not textures.has(id):textures[id]=load(ROOT+id+'.png')
	return textures[id]
func icon(id: String) -> Texture2D:
	if not icons.has(id):
		var cropped=AtlasTexture.new();cropped.atlas=texture(id);cropped.region=REGIONS[id];cropped.filter_clip=true;icons[id]=cropped
	return icons[id]
func sprite_rect(id: String,point: Vector2,width: float) -> Rect2:
	var region: Rect2=REGIONS[id]
	var scale=width/region.size.x
	# Anchor within the base footprint, not at the canvas edge or the roof.
	var anchor=Vector2(region.get_center().x,region.end.y-region.size.y*.15)
	return Rect2((point-anchor*scale).round(),texture(id).get_size()*scale)

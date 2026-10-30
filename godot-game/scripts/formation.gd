extends RefCounted
## Shared ground coordinates keep the camp preview and battle departure identical.
const Catalog=preload('res://scripts/data/catalog.gd')
const BATTLE_ORIGIN=Vector2(595,475)
const BATTLE_SCALE=Vector2(.91,.9)

static func cell_center(cell: int) -> Vector2:
	var field=Catalog.presentation('field')
	var columns=int(Catalog.data('balance/camp').columns)
	return field.camp_origin+Vector2(cell%columns,int(cell/float(columns)))*field.camp_spacing

static func battle_position(cell: int) -> Vector2:
	return (cell_center(cell)-BATTLE_ORIGIN)/BATTLE_SCALE

static func count(type: String,level: int=1) -> int:
	var counts=Catalog.data('balance/units').get(type,{}).get('formation_counts',[])
	if not counts.is_empty(): return int(counts[clampi(level,1,3)-1])
	return 3 if type=='medic' else 5 if type=='cavalry' else 9

static func offset(type: String,index: int,total: int,testudo: bool=false) -> Vector2:
	var columns=2 if type=='cavalry' else 3
	var rows=int(ceil(total/float(columns)))
	var spacing=Vector2(30,25) if type=='cavalry' else Vector2(22,24)
	return Vector2((columns-1)*.5-index%columns,int(index/float(columns))-(rows-1)*.5)*spacing*(.72 if testudo else 1.0)

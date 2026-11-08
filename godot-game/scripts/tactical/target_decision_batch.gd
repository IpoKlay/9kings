extends RefCounted
## Private to one synchronous ordered personal pass; never an eligibility snapshot.
## In-scope writers of eligibility, score fields or unit/decoy order must invalidate.
## hurt/heal, update_center, skill resolve/advance and spawn are the current writers.
var active=false
var unit: Dictionary={}
var target: Dictionary={}
var position: Vector2
var side: String
var kind: String
var order: String

func invalidate():
	unit={}
	target={}

func begin():
	invalidate()
	active=true

func end():
	active=false
	invalidate()

func matches(u: Dictionary) -> bool:
	return is_same(unit,u) and position==u.pos and side==u.side and kind==u.kind and order==u.get('order','auto')

func remember(u: Dictionary,value: Dictionary):
	unit=u;target=value
	position=u.pos;side=u.side;kind=u.kind;order=u.get('order','auto')

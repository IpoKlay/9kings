"""Bake schematic march corridors from the existing atlas mask; never edit the atlas.
Uses Pillow. The resulting paths are geographic game routes, not attested Roman roads.
"""
import heapq,json,math
from functools import lru_cache
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
GRID=8
positions=json.loads((ROOT/'data/generated/atlas_positions.json').read_text())
locations=json.loads((ROOT/'data/content/locations.json').read_text())
nodes={n['id']:n for n in locations}
edges=json.loads((ROOT/'data/content/routes.json').read_text())['edges']
mask=Image.open(ROOT/'assets/expedition/shore_distance.png').convert('RGB')
width,height=mask.width*2//GRID,mask.height*2//GRID
wet=[[mask.getpixel((int((x+.5)*GRID/2),int((y+.5)*GRID/2)))[1]>127 for x in range(width)] for y in range(height)]
sea_edges={('246369','265883'),('265883','266090'),('462503','314921'),('442509','481818'),('579885','599612'),('599612','590030'),('590030','639042'),('590030','639051')}
# The duplicated Oea marker represents a broad inland approach, not a second city.
visual_sites={'344456_inland':[2696,1990]}
entries={n['act']:n['id'] for n in locations if n['step']==1}
for act in [2,3]:edges.append(['423025',entries[act]])
edges.append(['727070',entries[1]])
def point(cell):return [(cell[0]+.5)*GRID,(cell[1]+.5)*GRID]
def valid(cell,sea):return 0<=cell[0]<width and 0<=cell[1]<height and wet[cell[1]][cell[0]]==sea
def nearest(p,sea):
 c=(int(p[0]/GRID),int(p[1]/GRID))
 for r in range(30):
  candidates=[(c[0]+dx,c[1]+dy) for dx in range(-r,r+1) for dy in range(-r,r+1) if max(abs(dx),abs(dy))==r and valid((c[0]+dx,c[1]+dy),sea)]
  if candidates:return min(candidates,key=lambda v:math.dist(p,point(v)))
 raise ValueError(('No shore access',p,sea))
def line_clear(a,b,sea):
 # Check each few map pixels, so simplification cannot cut across a peninsula.
 length=math.dist(a,b);n=max(1,math.ceil(length/2))
 for i in range(n+1):
  x=(a[0]+(b[0]-a[0])*i/n)/2;y=(a[1]+(b[1]-a[1])*i/n)/2
  if (mask.getpixel((int(x),int(y)))[1]>127)!=sea:return False
 return True
@lru_cache(maxsize=None)
def clear_step(a,b,sea):return line_clear(point(a),point(b),sea)
def path(start,end,sea):
 a=nearest(start,sea);b=nearest(end,sea)
 costs={a:0};previous={};pending=[(math.dist(a,b),0,a)]
 while pending:
  _,cost,c=heapq.heappop(pending)
  if cost!=costs[c]:continue
  if c==b:break
  for dx,dy in [(1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)]:
   v=(c[0]+dx,c[1]+dy)
   if not valid(v,sea) or (dx and dy and (not valid((c[0]+dx,c[1]),sea) or not valid((c[0],c[1]+dy),sea))):continue
   if not clear_step(c,v,sea):continue
   step=math.hypot(dx,dy)
   new=cost+step
   if new>=costs.get(v,math.inf):continue
   costs[v]=new;previous[v]=c;heapq.heappush(pending,(new+math.dist(v,b),new,v))
 else:raise ValueError(('No geographic corridor',start,end,sea))
 cells=[b]
 while cells[-1]!=a:cells.append(previous[cells[-1]])
 points=[point(c) for c in reversed(cells)]
 # Preserve coastline bends, collapse only unobstructed intermediate points.
 simple=[points[0]];i=0
 while i<len(points)-1:
  j=len(points)-1
  while j>i+1 and not line_clear(points[i],points[j],sea):j-=1
  simple.append(points[j]);i=j
 return [list(map(lambda v:round(v,2),start))]+simple+[list(map(lambda v:round(v,2),end))]
result={'note':'Schematic geographic corridors sampled from the current atlas; not a historical road survey.','visual_sites':visual_sites,'edges':{}}
for a,b in edges:
 sea=(a,b) in sea_edges or (nodes[a]['act']!=nodes[b]['act'] and not (a=='423025' and b=='442509'))
 start=visual_sites.get(a,positions[a]);end=visual_sites.get(b,positions[b])
 points=path(start,end,sea)
 result['edges'][a+'>'+b]={'mode':'sea' if sea else 'land','points':points}
 print(a,b,'sea' if sea else 'land',len(points))
(ROOT/'data/generated/march_paths.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')

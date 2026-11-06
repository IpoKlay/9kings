shader_type canvas_item;
render_mode unshaded;
uniform sampler2D source_atlas : filter_nearest, repeat_disable;
// Offline only: derive a continuous floor from the approved SBS grass/soil tiles.
uniform vec4 projection=vec4(.76,-.68,.27,.4);
uniform vec2 screen_origin=vec2(940,510);
uniform vec2 world_origin=vec2(800,450);
const vec2 EDGE[18]=vec2[18](vec2(310,165),vec2(580,150),vec2(900,180),vec2(1300,175),vec2(1610,220),vec2(1710,380),vec2(1730,550),vec2(1660,700),vec2(1640,860),vec2(1490,960),vec2(1160,970),vec2(850,970),vec2(600,850),vec2(450,700),vec2(320,620),vec2(350,470),vec2(300,330),vec2(290,240));
const vec3 GRASS[7]=vec3[7](vec3(.149,.239,.169),vec3(.212,.314,.208),vec3(.275,.388,.235),vec3(.341,.459,.286),vec3(.416,.525,.337),vec3(.518,.600,.416),vec3(.612,.678,.502));
const vec3 SOIL[7]=vec3[7](vec3(.251,.239,.188),vec3(.318,.282,.212),vec3(.404,.357,.255),vec3(.482,.420,.302),vec3(.569,.490,.349),vec3(.659,.573,.424),vec3(.741,.647,.490));

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 cell=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(cell),hash(cell+vec2(1,0)),f.x),mix(hash(cell+vec2(0,1)),hash(cell+vec2(1,1)),f.x),f.y);
}
float boundary(vec2 p) {
	float d=1e10;bool inside=false;
	for(int i=0;i<18;i++) {
		vec2 a=EDGE[i],b=EDGE[(i+17)%18],v=b-a,w=p-a;
		vec2 q=w-v*clamp(dot(w,v)/dot(v,v),0.0,1.0);
		d=min(d,dot(q,q));
		if((a.y>p.y)!=(b.y>p.y)) {
			if(p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) inside=!inside;
		}
	}
	return sqrt(d)*(inside?-1.0:1.0);
}
vec2 mirror_uv(vec2 p) { return 1.0-abs(mod(p,2.0)-1.0); }
float source_luma(vec2 at,bool dirt) {
	vec2 sq=mirror_uv(at);
	// Stay inside the diamond: black transparent-key borders are never sampled.
	vec2 origin=dirt?vec2(256,640):vec2(0,384);
	vec2 uv=(origin+vec2(128.0+(sq.x-sq.y)*110.0,64.0+(sq.x+sq.y-1.0)*54.0))/768.0;
	return dot(texture(source_atlas,uv).rgb,vec3(.299,.587,.114));
}
float material_luma(vec2 p,bool dirt) {
	// Overlapping, mirrored source samples stay continuous across former tile edges.
	float a=source_luma(p/167.0+vec2(1.31,.37),dirt);
	float b=source_luma(vec2(p.y,-p.x)/223.0+vec2(.71,2.13),dirt);
	float c=source_luma((p+vec2(p.y*.31,p.x*.23))/293.0+vec2(3.7,.19),dirt);
	return a*.65+b*.25+c*.10;
}
void fragment() {
	vec2 pixel=floor(UV*vec2(960,540));
	vec2 p=(pixel+.5)*2.0;
	float edge=noise(p*.016)*32.0+noise(p*.043)*12.0;
	float coverage=clamp((-boundary(p)-12.0+edge)/46.0,0.0,1.0);
	if(coverage<=hash(pixel+vec2(59,113))) discard;
	vec2 v=p-screen_origin;
	float det=projection.x*projection.w-projection.y*projection.z;
	vec2 world=world_origin+vec2(projection.w*v.x-projection.y*v.y,-projection.z*v.x+projection.x*v.y)/det;
	float camp=length((world-vec2(310,445))/vec2(390,235));
	float bare=length((world-vec2(1040,650))/vec2(170,110));
	float uneven=(noise(world*.014)-.5)*.5+(noise(world*.039)-.5)*.20;
	float soil_coverage=1.0-smoothstep(.52,1.05,min(camp,bare)+uneven);
	bool dirt=soil_coverage>hash(pixel+vec2(173,27));
	float luma=material_luma(world,dirt);
	float value=clamp(.5+((luma-.12)/.48-.5)*1.35+(noise(world*.021)-.5)*.10,0.0,1.0);
	int level=int(floor(value*6.99));
	COLOR=vec4(dirt?SOIL[level]:GRASS[level],1.0);
}

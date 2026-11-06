shader_type canvas_item;
render_mode unshaded;

uniform float sea_time=0.0;
uniform sampler2D shore_distance : filter_nearest, repeat_disable;
uniform bool coast_enabled=true;
uniform bool wind_enabled=true;
uniform int gust_count=0;
uniform vec4 gust_patches[12];
uniform vec4 gust_flows[12];
const vec2 ATLAS_SIZE=vec2(2880.0,1260.0);

float hash(vec2 p) {
	return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}

float coast_noise(vec2 p) {
	vec2 cell=floor(p);
	vec2 f=fract(p);f=f*f*(3.0-2.0*f);
	return mix(mix(hash(cell),hash(cell+vec2(1.0,0.0)),f.x),mix(hash(cell+vec2(0.0,1.0)),hash(cell+vec2(1.0)),f.x),f.y);
}

// A distorted cellular ridge network matches the connected, changing water
// marks in the reference. It is a flat four-color pattern, never a height map.
vec2 water_ridges(vec2 p,float t) {
	vec2 flow=p-vec2(2.0,.65)*t;
	flow+=vec2(sin(flow.y*.19+t*.24),sin(flow.x*.15-t*.20))*3.8;
	vec2 warp=vec2(coast_noise(flow/13.0),coast_noise(flow/17.0+19.0))-.5;
	vec2 q=(flow+warp*12.0)/vec2(20.0,13.0);
	vec2 cell=floor(q);
	vec2 local=fract(q);
	float first=20.0;
	float second=20.0;
	for (int y=-1;y<=1;y++) {
		for (int x=-1;x<=1;x++) {
			vec2 offset=vec2(float(x),float(y));
			vec2 id=cell+offset;
			vec2 seed=vec2(hash(id),hash(id+37.0));
			vec2 site=.5+(seed-.5)*.64+sin(seed*6.283+t*.52)*.10;
			vec2 delta=offset+site-local;
			float d=dot(delta,delta);
			if (d<first) { second=first;first=d; }
			else { second=min(second,d); }
		}
	}
	return vec2(sqrt(second)-sqrt(first),coast_noise(flow/vec2(37.0,25.0)+11.0));
}

float wind_at(vec2 p) {
	float total=0.0;
	if (!wind_enabled) { return total; }
	for (int i=0;i<12;i++) {
		if (i>=gust_count) { break; }
		vec4 patch=gust_patches[i];
		vec4 gust=gust_flows[i];
		vec2 delta=p-patch.xy;
		vec2 side=vec2(-gust.y,gust.x);
		vec2 local=vec2(dot(delta,gust.xy),dot(delta,side))/patch.zw;
		// Broad, uneven lobes; no concentric ring, drawn boundary, or fine spray.
		float rim=1.0+(coast_noise(p/57.0+gust.w*21.0)-.5)*.36;
		float coverage=1.0-smoothstep(.20,rim,length(local));
		total+=coverage*gust.z;
	}
	return clamp(total,0.0,1.0);
}

void fragment() {
	// The original land and water texels stay fixed: no refraction or 3D light.
	vec4 original=texture(TEXTURE,UV);
	vec4 result=original;
	vec2 shore=texture(shore_distance,UV).rg;
	if (shore.g>.5 && original.b-original.r>.16 && original.g-original.r>.08) {
		vec2 p=floor(UV*ATLAS_SIZE);
		float t=floor(sea_time*12.0)/12.0;
		vec2 pattern=water_ridges(p,t);
		float breeze=wind_at(p);
		// Irregular widths stay connected. A breeze strengthens the SAME network,
		// rather than overlaying another decorative stroke or circle.
		float width=.055+pattern.y*.120+breeze*.025;
		if (pattern.x<width) {
			result.rgb=vec3(.157,.337,.435);
			if (pattern.x<width*.65) { result.rgb=vec3(.196,.380,.494); }
			if (pattern.y>.52 && pattern.x<width*.38) { result.rgb=vec3(.224,.420,.525); }
			if (breeze>.32 && pattern.x<width*.50) { result.rgb=vec3(.282,.494,.584); }
		}
	}
	if (coast_enabled && shore.g>.5 && shore.r<.65) {
		vec2 p=floor(UV*ATLAS_SIZE/2.0)*2.0;
		float depth=shore.r*32.0;
		float patch=coast_noise(p/110.0);
		float cycle=fract(floor(sea_time*8.0)/8.0/(6.0+patch*3.0)+coast_noise(p/170.0+31.0)*2.0);
		// Approach the actual coast, pause briefly, then retreat and break up.
		float front=cycle<.48?mix(18.0,2.0,cycle/.48):mix(2.0,12.0,clamp((cycle-.53)/.27,0.0,1.0));
		front=floor(front/2.0)*2.0;
		float grain=hash(floor(p/vec2(6.0,4.0)));
		bool crest=abs(depth-front)<1.25;
		bool broken=grain>(cycle<.53?.18:.48);
		if (cycle<.80 && crest && broken) {
			result.rgb=cycle<.53?vec3(.64,.78,.74):vec3(.44,.65,.65);
		}
	}
	COLOR=result;
}

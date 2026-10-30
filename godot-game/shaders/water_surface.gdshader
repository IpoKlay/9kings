shader_type canvas_item;
render_mode unshaded;

uniform float flow_time = 0.0;
uniform float flow_speed = 1.0;
uniform float ripple_strength = 0.12;
uniform int water_count = 0;
uniform vec2 water_points[24];
const vec2 FIELD_SIZE = vec2(1920.0, 1080.0);

// A hand-traced water footprint plus a color guard prevents any shore/land warp.
float water_color(vec3 c) {
	return smoothstep(0.035, 0.085, c.b-c.r) * smoothstep(0.025, 0.08, c.g-c.r)
		* smoothstep(-0.15, -0.03, c.b-c.g);
}
vec2 water_region(vec2 p) {
	bool inside = false;
	float shore = 2000.0;
	for (int i=0; i<24; i++) {
		if (i>=water_count) { break; }
		int j=(i+1)%water_count;
		vec2 a=water_points[i];
		vec2 b=water_points[j];
		if ((a.y>p.y)!=(b.y>p.y)) {
			if (p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) { inside=!inside; }
		}
		// The image boundary is open water, not a shoreline.
		if (!(a.x<=0.0 && b.x<=0.0) && !(a.y>=1080.0 && b.y>=1080.0)) {
			vec2 edge=b-a;
			float along=clamp(dot(p-a,edge)/max(dot(edge,edge),0.001),0.0,1.0);
			shore=min(shore,length(p-a-edge*along));
		}
	}
	return vec2(inside?1.0:0.0,shore);
}
void fragment() {
	vec4 original=texture(TEXTURE,UV);
	vec4 result=original;
	vec2 p=floor(UV*FIELD_SIZE/2.0)*2.0;
	if (p.x<640.0 && p.y>580.0 && water_count>=3) {
		vec2 region=water_region(p);
		float wet=region.x*water_color(original.rgb);
		if (wet>0.001) {
			float t=flow_time*flow_speed;
			float interior=smoothstep(3.0,16.0,region.y);
			// Gentle moving refraction, snapped to the native pixel grid.
			vec2 motion=vec2(sin(p.y*.071-t*.73)+.45*sin(p.x*.043+t*.41),
				.65*cos(p.x*.061+p.y*.025-t*.53))*2.0*interior;
			vec2 sample_uv=UV+round(motion/2.0)*2.0/FIELD_SIZE;
			vec4 refracted=texture(TEXTURE,sample_uv);
			float safe=water_color(refracted.rgb)*water_region(sample_uv*FIELD_SIZE).x;
			result=mix(original,refracted,wet*safe*.72);
			// Uneven bands drift across the water instead of blinking in place.
			float wave=sin(p.y*.19+p.x*.045-t*1.25+sin(p.x*.028+t*.25)*1.3);
			float broken=smoothstep(-.35,.55,sin(p.x*.077-t*.33+sin(p.y*.025)*2.0))
				*(.45+.55*(.5+.5*sin(p.x*.019+p.y*.031+t*.21)));
			float crest=smoothstep(.73,.99,wave)*broken;
			float crossing=smoothstep(.89,1.0,sin(p.y*.29-p.x*.065-t*.76));
			float shore_wave=smoothstep(.67,.98,sin(region.y*.27-t*1.45));
			float foam=shore_wave*exp(-region.y/22.0)*.13;
			float light=(crest*ripple_strength+crossing*ripple_strength*.24)*interior+foam;
			result.rgb=mix(result.rgb,vec3(.63,.79,.76),light*wet);
			result.rgb-=vec3(.018,.012,.009)*(1.0-crest)*interior*wet;
		}
	}
	COLOR=result;
}

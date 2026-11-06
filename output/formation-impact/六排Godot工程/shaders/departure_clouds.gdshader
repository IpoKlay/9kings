shader_type canvas_item;
render_mode unshaded;
uniform float opacity : hint_range(0.0,1.0) = 0.0;
uniform vec4 lobes = vec4(0.0);
uniform vec4 shadow_ink : source_color;
uniform vec4 mid_ink : source_color;
uniform vec4 light_ink : source_color;
uniform vec4 highlight_ink : source_color;

float ellipse(vec2 p, vec2 center, vec2 radii) {
    return length((p-center)/radii)-1.0;
}
float cloud(vec2 p) {
    float d=ellipse(p,vec2(0.49,0.65),vec2(0.43,0.23));
    d=min(d,ellipse(p,vec2(0.22,0.49+lobes.x*0.06),vec2(0.20,0.24)));
    d=min(d,ellipse(p,vec2(0.43,0.38+lobes.y*0.08),vec2(0.24,0.28)));
    d=min(d,ellipse(p,vec2(0.65,0.40+lobes.z*0.06),vec2(0.22,0.27)));
    return min(d,ellipse(p,vec2(0.80,0.56+lobes.w*0.05),vec2(0.16,0.22)));
}
void fragment() {
    // Each rectangle is one cloud, drawn in whole pixels on the small canvas.
    float d=cloud(UV);
    vec4 ink=light_ink;
    if(cloud(UV+vec2(0.018,0.095))>0.0) ink=shadow_ink;
    else if(cloud(UV+vec2(0.0,0.055))>0.0) ink=mid_ink;
    else if(cloud((UV-vec2(0.48,0.46))*1.18+vec2(0.48,0.49))<0.0) ink=highlight_ink;
    COLOR=vec4(ink.rgb,step(d,0.0)*opacity);
}

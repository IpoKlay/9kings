"""Reproduce numeric comparisons; requires the already extracted official public build.
The original renderer is replaced by a neutral shader only in this isolated probe.
The controlled run substitutes global random calls with a seeded instance; physics
method statements otherwise remain unchanged. This does not run an original battle.
"""
from pathlib import Path
import hashlib,json,shutil,subprocess
base=Path(__file__).resolve().parents[3];out=Path(__file__).resolve().parent
source=Path('/private/tmp/sword-banner-reference/analysis/scripts/ragdoll_effect.gd');project=Path('/private/tmp/eagle-corpse-source-probe');project.mkdir(exist_ok=True)
(project/'project.godot').write_text('[application]\nconfig/name="Corpse numerical probe"\n[autoload]\nRenderConfig="*res://render_config.gd"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
(project/'render_config.gd').write_text('extends Node\nvar enable_outline=false\nvar enable_dither=false\n')
(project/'shaders').mkdir(exist_ok=True);(project/'shaders/ragdoll.gdshader').write_text('shader_type canvas_item;\nuniform float alpha=1.;\nvoid fragment(){COLOR=vec4(1.,1.,1.,alpha);}\n')
text=source.read_text();modified=text.replace('extends Node2D','extends Node2D\nvar _probe_random=RandomNumberGenerator.new()').replace('randf_range(', '_probe_random.randf_range(').replace('randf()', '_probe_random.randf()')
(project/'original.gd').write_text(modified)
shutil.copy(base/'godot-game/scripts/tactical/corpse_motion.gd',project/'local.gd');shutil.copy(out/'source_probe.gd',project/'probe.gd')
(project/'data/presentation').mkdir(parents=True,exist_ok=True);shutil.copy(base/'godot-game/data/presentation/corpse_rigs.json',project/'data/presentation/corpse_rigs.json')
p=subprocess.run(['/Users/ip/Downloads/Godot.app/Contents/MacOS/Godot','--headless','--path',str(project),'--script','res://probe.gd'],capture_output=True,text=True,timeout=60)
(out/'source-probe-controlled.log').write_text(p.stdout+p.stderr)
assert p.returncode==0 and 'SCRIPT ERROR' not in p.stdout+p.stderr and '9 cases, 0 failures' in p.stdout,p.stdout+p.stderr
(out/'probe-provenance.json').write_text(json.dumps({'original_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'substitutions':['RenderConfig autoload with outline/ditherfalse','neutral shader at the expected resource path; no original art','global randf and randf_range replaced by seeded RandomNumberGenerator for controlled input'],'exact_original_unmodified_run':'source-probe-global-rng.json: ordinary constrained skeleton agrees; random dependent traces differ because original global RNG does not equal the isolated local RNG','probe':'9 archetype cases ×150 visual callbacks at60fps; positions, weapon angle, shield positions and frozen flags; tolerance .001','not_verified':['original game full scene and source engine version','global RNG stream equivalence','prone pixel-art retargeting equivalent to reference procedural renderer']},indent=2)+'\n')
print(p.stdout)

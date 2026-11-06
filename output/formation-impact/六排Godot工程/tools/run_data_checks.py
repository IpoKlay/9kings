"""Read-only regression suites; generated logs/screenshots live in output/data-organization.
Usage: python3 tools/run_data_checks.py --godot /absolute/path/to/Godot --suite headless|native|all
"""
import argparse,json,re,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--suite',choices=['headless','native','all'],default='headless');args=p.parse_args()
root=Path(__file__).resolve().parents[1];out=root.parent/'output/data-organization/after';out.mkdir(parents=True,exist_ok=True)
headless=['test_data_layers','test_campaign','test_expedition','test_expedition_routes','test_city_waves','test_random_theaters','test_expedition_flow','test_map_locale']
native=['test_menu_environments','test_card_hand','test_card_face','test_card_swipe','test_card_audio','test_supply_to_battle','test_city_waves_ui','test_expedition_layout','test_water_surface','test_atlas_sea','test_theater_wind','test_pixel_fonts','test_report_dialog','test_expedition_ui','test_data_visual_parity']
tasks=[]
if args.suite in ['headless','all']:tasks+=[('tools/validate_data',True)]+[('tests/'+s,True) for s in headless]
if args.suite in ['native','all']:tasks+=[('tests/'+s,False) for s in native]
results=[]
for name,head in tasks:
 cmd=[args.godot]+(['--headless'] if head else [])+['--path',str(root),'--script','res://'+name+'.gd','--log-file',str(out/(Path(name).name+'-engine.log'))]
 try:
  run=subprocess.run(cmd,capture_output=True,text=True,timeout=300)
  output=run.stdout+run.stderr
  bad=bool(re.search(r'SCRIPT ERROR|FAIL:|DATA ERROR|Failed to load script',output))
  result={'test':Path(name).name,'exit':run.returncode,'passed':run.returncode==0 and not bad,'summary':[s for s in output.splitlines() if re.search(r'checks|failures|snapshots|differences|FAIL:|DATA ERROR|SCRIPT ERROR',s)]}
 except subprocess.TimeoutExpired as exc:
  output=(exc.stdout or b'').decode(errors='replace')+(exc.stderr or b'').decode(errors='replace');result={'test':Path(name).name,'passed':False,'reason':'timeout'}
 (out/(Path(name).name+'.log')).write_text(output)
 results.append(result);print(json.dumps(result,ensure_ascii=False),flush=True)
 (out/(args.suite+'-checks.json')).write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)

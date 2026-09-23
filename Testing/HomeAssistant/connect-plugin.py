#!/usr/bin/env python3
"""Configure only the new/disposable connection, never replace another home."""
import json,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[2]
credentials=json.loads((root/'build/test-home/credentials.json').read_text())
assert credentials['server']=='http://127.0.0.1:18123'
processes=subprocess.check_output(['pgrep','-fl','HomeAssistantPlugin'],text=True).splitlines()
exe=next((line.split(' ',1)[1].removesuffix(' --neronook-plugin') for line in processes if '/NeroNook/Plugins/' in line and line.endswith(' --neronook-plugin')),None)
if not exe:raise SystemExit('Run the installed Home Assistant plugin in NeroNook first.')
settings=pathlib.Path.home()/'Library/Application Support/NeroNookPlugins/cafe.nero.plugin.homeassistant/settings.json'
old=json.loads(settings.read_text()) if settings.exists() else {}
if old.get('server','') not in ['',credentials['server']]:raise SystemExit('Another home is already configured; leaving it unchanged.')
subprocess.run(['xcrun','swiftc','-parse-as-library',str(root/'Testing/HomeAssistant/ImportCredential.swift'),'-o',str(root/'build/test-home/import-credential')],check=True)
result=subprocess.run([str(root/'build/test-home/import-credential')],input=json.dumps({'server':credentials['server'],'plugin_token':credentials['plugin_token'],'executable':exe}),text=True,capture_output=True)
if result.returncode:raise SystemExit('Could not save the test token to Keychain; user approval may be needed.')
settings.parent.mkdir(parents=True,exist_ok=True)
value={'server':credentials['server'],'favorites':['light.desk_lamp','light.reading_light','switch.desk_fan','sensor.office_temperature','sensor.office_humidity','light.offline_light'],'controls':['light.desk_lamp','light.reading_light','switch.desk_fan','scene.work_mode','scene.evening']}
tmp=settings.with_suffix('.test-tmp');tmp.write_text(json.dumps(value));tmp.replace(settings)
print('Test connection configured. Restart this plugin in NeroNook and approve its Keychain prompt if requested.')

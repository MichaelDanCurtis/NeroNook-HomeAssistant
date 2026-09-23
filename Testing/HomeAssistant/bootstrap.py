#!/usr/bin/env python3
"""Create a disposable local test account using Home Assistant's onboarding API.
Secrets stay in the ignored 0600 test credentials file; never print them.
"""
import json,os,pathlib,secrets,subprocess,urllib.request,urllib.parse
root=pathlib.Path(__file__).resolve().parents[2]
base='http://127.0.0.1:18123';vault=root/'build/test-home/credentials.json'
def request(path,data=None,token=None,form=False,method=None):
 headers={};body=None
 if data is not None:
  body=urllib.parse.urlencode(data).encode() if form else json.dumps(data).encode();headers['Content-Type']='application/x-www-form-urlencoded' if form else 'application/json'
 if token:headers['Authorization']='Bearer '+token
 req=urllib.request.Request(base+path,data=body,headers=headers,method=method)
 with urllib.request.urlopen(req,timeout=30) as r:return json.load(r)
def save(value):
 fd=os.open(vault,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
 with os.fdopen(fd,'w') as f:json.dump(value,f)
steps=request('/api/onboarding')
if vault.exists():creds=json.loads(vault.read_text())
else:
 if next(s for s in steps if s['step']=='user')['done']:raise SystemExit('Test account already exists; do not overwrite it. Restore its ignored credentials file.')
 creds={'username':'neronook_test','password':secrets.token_urlsafe(28),'server':base}
 save(creds)
 result=request('/api/onboarding/users',dict(name='NeroNook Test',username=creds['username'],password=creds['password'],client_id=base+'/',language='en'))
 auth=request('/auth/token',dict(grant_type='authorization_code',code=result['auth_code'],client_id=base+'/'),form=True)
 creds.update(auth);save(creds)
# All following configuration affects only the new loopback test installation.
for step in ['core_config','analytics','integration']:
 if next(s for s in steps if s['step']==step)['done']:continue
 payload={'client_id':base+'/','redirect_uri':base+'/'} if step=='integration' else {}
 request('/api/onboarding/'+step,payload,creds['access_token'])
ws_program=r'''
import asyncio,json,sys
import aiohttp
async def main():
 auth=json.load(sys.stdin);counter=0
 async with aiohttp.ClientSession() as session:
  async with session.ws_connect('http://127.0.0.1:8123/api/websocket') as ws:
   await ws.receive_json();await ws.send_json({'type':'auth','access_token':auth.get('plugin_token',auth['access_token'])});assert (await ws.receive_json())['type']=='auth_ok'
   async def call(kind,**kwargs):
    nonlocal counter
    counter+=1;await ws.send_json(dict(id=counter,type=kind,**kwargs))
    while True:
     m=await ws.receive_json()
     if m.get('id')==counter:
      if not m.get('success'):raise RuntimeError('Test-home API declined '+kind)
      return m.get('result')
   token=auth.get('plugin_token') or await call('auth/long_lived_access_token',client_name='NeroNook Docker Test Plugin',lifespan=30)
   areas=await call('config/area_registry/list')
   existing={a['name']:a['area_id'] for a in areas}
   for name in ['Office','Living Room']:
    if name not in existing:existing[name]=(await call('config/area_registry/create',name=name))['area_id']
   entities=await call('config/entity_registry/list')
   assigned=0
   for e in entities:
    id=e['entity_id']
    if id in ['light.desk_lamp','switch.desk_fan','sensor.office_temperature','sensor.office_humidity']:
     await call('config/entity_registry/update',entity_id=id,area_id=existing['Office']);assigned+=1
    elif id in ['light.reading_light','light.offline_light']:
     await call('config/entity_registry/update',entity_id=id,area_id=existing['Living Room']);assigned+=1
   print(json.dumps({'plugin_token':token,'rooms_assigned':assigned}))
asyncio.run(main())
'''
result=subprocess.run(['docker','exec','-i','neronook-homeassistant-test','python','-c',ws_program],input=json.dumps(creds),text=True,capture_output=True,check=True)
provisioned=json.loads(result.stdout);creds['plugin_token']=provisioned['plugin_token'];save(creds)
login=root/'build/test-home/login.txt'
fd=os.open(login,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
with os.fdopen(fd,'w') as f:f.write('NeroNook disposable Docker test home\n\nAddress: '+base+'\nUsername: '+creds['username']+'\nPassword: '+creds['password']+'\n\nThis is only the local test home, not an Apple or household account.\n')
states=request('/api/states',token=creds['plugin_token'])
print(json.dumps({'server':base,'entities':len(states),'rooms_assigned':provisioned['rooms_assigned'],'virtual_devices':[s['entity_id'] for s in states if s['entity_id'].startswith(('light.','switch.','sensor.','scene.'))]}))

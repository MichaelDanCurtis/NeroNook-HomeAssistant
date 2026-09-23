#!/usr/bin/env python3
"""Isolated SDK handshake; never loads the user's settings or Keychain."""
import json, os, pathlib, selectors, subprocess, time, uuid, sys
cards_mode = "--cards" in sys.argv
root=pathlib.Path(__file__).resolve().parents[1]
p=subprocess.Popen([str(root/'build/Home Assistant Module.app/Contents/MacOS/HomeAssistantPlugin'),'--neronook-plugin','--protocol-test'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
session=str(uuid.uuid4());plugin='cafe.nero.plugin.homeassistant';buffer=b'';last=-1
selector=selectors.DefaultSelector();selector.register(p.stdout,selectors.EVENT_READ)
def send(kind,**kwargs):
 p.stdin.write((json.dumps(dict(apiVersion=1,type=kind,pluginID=plugin,session=session,sequence=0,**kwargs))+'\n').encode());p.stdin.flush()
def wait_for(predicate):
 global buffer,last
 end=time.monotonic()+15
 while time.monotonic()<end:
  if b'\n' not in buffer:
   if not selector.select(1):continue
   data=os.read(p.stdout.fileno(),131072)
   if not data:raise AssertionError('Plugin exited')
   buffer+=data
  while b'\n' in buffer:
   line,buffer=buffer.split(b'\n',1);m=json.loads(line)
   assert len(line)<131072 and m['sequence']>last;last=m['sequence']
   assert m['pluginID']==plugin and m['session'].lower()==session.lower()
   if predicate(m):return m
 raise AssertionError('Plugin response deadline')
try:
 send('hello',features=['actions-v1','dashboard-v1','panels-v1','diagrams-v1'] + (['control-cards-v1'] if cards_mode else []))
 ready=wait_for(lambda m:m['type']=='ready');assert 'actions-v1' in ready['features']
 snap=wait_for(lambda m:m['type']=='snapshot')['snapshot']
 assert [p['title'] for p in snap['panels']]==['Favorites','Rooms','Scenes']
 assert len(snap['activity'])<=100
 for panel in snap['panels']:
  if cards_mode: assert panel['cards'] == [] and 'diagrams' not in panel
  else:
   diagram=panel['diagrams'][0];assert diagram['width']/diagram['height']==16/9
 request=str(uuid.uuid4());send('bus',bus=dict(operation='execute',requestID=request,address=dict(plugin=plugin,name='set_power'),values=dict(server='http://127.0.0.1:9',entity='lock.front',on=True)))
 result=wait_for(lambda m:m['type']=='bus' and m.get('bus',{}).get('requestID','').lower()==request.lower())
 assert result['bus']['update']['phase']=='failed'
 print('PASS: SDK handshake, content-only tabs, 16:9 panels, one-line status, unsafe/unconnected target rejected.')
finally:
 selector.close();p.stdin.close()
 try:p.wait(timeout=3)
 except subprocess.TimeoutExpired:p.terminate();p.wait(timeout=3)

#!/usr/bin/env python3
"""Production module + disposable loopback fixture; never reads saved credentials."""
import json, os, pathlib, plistlib, selectors, shutil, subprocess, tempfile, time, uuid
root = pathlib.Path(__file__).resolve().parents[1]
binary = root / '.build/debug/HomeAssistantPlugin'
with tempfile.TemporaryDirectory(prefix='nook-inline-') as directory:
    folder = pathlib.Path(directory)
    log = folder / 'requests.log'
    fixture = subprocess.Popen(['python3', str(root/'scripts/fixture-server.py'), 'normal', str(log)], stdout=subprocess.PIPE, text=True)
    port = int(fixture.stdout.readline())
    app = folder / 'Inline Fixture.app'
    (app/'Contents/MacOS').mkdir(parents=True)
    shutil.copy2(binary, app/'Contents/MacOS/HomeAssistantPlugin')
    with open(app/'Contents/Info.plist', 'wb') as output:
        plistlib.dump(dict(CFBundleExecutable='HomeAssistantPlugin', CFBundleIdentifier='cafe.nero.inline.test', CFBundlePackageType='APPL', NeroHomeFixture=f'http://127.0.0.1:{port}'), output)
    process = subprocess.Popen([str(app/'Contents/MacOS/HomeAssistantPlugin'), '--neronook-plugin'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    session = str(uuid.uuid4()); selector = selectors.DefaultSelector(); selector.register(process.stdout, selectors.EVENT_READ); buffer = b''
    def send(action=None):
        message = dict(apiVersion=1, type='action' if action else 'hello', pluginID='cafe.nero.plugin.homeassistant', session=session, sequence=0)
        if action: message['action'] = action
        else: message['features'] = ['control-cards-v1','actions-v1']
        process.stdin.write((json.dumps(message)+'\n').encode()); process.stdin.flush()
    def wait(predicate):
        global buffer
        deadline=time.monotonic()+12
        while time.monotonic()<deadline:
            if b'\n' not in buffer:
                if not selector.select(0.2): continue
                chunk=os.read(process.stdout.fileno(),131072)
                assert chunk, 'Module exited'; buffer+=chunk
            while b'\n' in buffer:
                line,buffer=buffer.split(b'\n',1); assert len(line)<=131072
                message=json.loads(line)
                if message['type']=='snapshot' and predicate(message['snapshot']): return message['snapshot']
        raise AssertionError('Timed out waiting for inline snapshot')
    def card(snapshot, title):
        return next(c for p in snapshot['panels'] for c in p.get('cards',[]) if c['title']==title)
    def calls(): return log.read_text().splitlines().count('call_service') if log.exists() else 0
    try:
        send()
        initial=wait(lambda s:s['badge']=='Live')
        lamp=card(initial,'Desk lamp'); assert lamp['value']=='On'
        action=lamp['actions'][0]; assert action['label']=='Turn off' and action['enabled'] and action['confirmation']
        fan=card(initial,'Desk fan'); assert not fan['actions'][0]['enabled']
        offline=card(initial,'Offline light'); assert not offline['actions'][0]['enabled']
        lock=card(initial,'Front door'); assert lock['actions']==[]
        send(fan['actions'][0]['id']); send('not_advertised')
        wait(lambda s:s['badge']=='Live'); assert calls()==0
        send(action['id'])
        result=wait(lambda s:s['badge']=='Live' and card(s,'Desk lamp')['value']=='Off')
        assert calls()==1 and 'confirmed' in result['status'].lower()
        send(action['id']) # Old state/action is no longer advertised.
        wait(lambda s:s['badge']=='Live'); assert calls()==1
        send(card(result,'Desk lamp')['actions'][0]['id'])
        result=wait(lambda s:s['badge']=='Live' and card(s,'Desk lamp')['value']=='On')
        assert calls()==2
        scene=card(result,'Evening')['actions'][0]; assert scene['enabled']
        send(scene['id'])
        wait(lambda s:s['badge']=='Live' and 'accepted' in s['status'].lower()); assert calls()==3
        print('PASS: actual inline action messages change the fixture light off/on with confirmed readback; scene accepted; disabled, unknown and stale actions send no commands. No Keychain or household access.')
    finally:
        selector.close();process.stdin.close()
        try:process.wait(timeout=3)
        except subprocess.TimeoutExpired:process.terminate();process.wait(timeout=3)
        fixture.terminate();fixture.wait(timeout=3)

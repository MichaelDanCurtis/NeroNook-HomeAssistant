#!/usr/bin/env python3
"""Loopback-only HA protocol fixture. No household connection or real credential."""
import base64, hashlib, json, socket, struct, sys, threading
mode = sys.argv[1] if len(sys.argv) > 1 else 'normal'
log = sys.argv[2] if len(sys.argv) > 2 else None
server = socket.socket(); server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); server.bind(('127.0.0.1', 0)); server.listen()
print(server.getsockname()[1], flush=True)
def record(kind):
    if log:
        with open(log, 'a') as f: f.write(kind+'\n')
def exact(c,n):
    b=b''
    while len(b)<n:
        d=c.recv(n-len(b))
        if not d: raise EOFError()
        b+=d
    return b
def send(c,obj):
    b=json.dumps(obj).encode(); n=len(b)
    head=bytes([0x81,n]) if n<126 else bytes([0x81,126])+struct.pack('!H',n)
    c.sendall(head+b)
def read(c):
    first,second=exact(c,2); n=second&127
    if n==126:n=struct.unpack('!H',exact(c,2))[0]
    elif n==127:n=struct.unpack('!Q',exact(c,8))[0]
    if n>100000:raise EOFError()
    mask=exact(c,4) if second&128 else None; b=exact(c,n)
    if mask:b=bytes(v^mask[i%4] for i,v in enumerate(b))
    if first&15==8:raise EOFError()
    return json.loads(b)
def entity(id,state,name,attrs=None):
    return dict(entity_id=id,state=state,attributes=dict(friendly_name=name,**(attrs or {})),last_updated='2026-09-22T12:00:00Z')
def handle(c):
    try:
        headers=b''
        while b'\r\n\r\n' not in headers:headers+=exact(c,1)
        if mode=='redirect':
            c.sendall(b'HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:9/api/websocket\r\nContent-Length: 0\r\n\r\n');return
        key=next(line.split(b':',1)[1].strip() for line in headers.split(b'\r\n') if line.lower().startswith(b'sec-websocket-key:'))
        accept=base64.b64encode(hashlib.sha1(key+b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest())
        c.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+b'\r\n\r\n')
        send(c,{'type':'auth_required'});auth=read(c)
        if mode=='auth_rejected':send(c,{'type':'auth_invalid'});return
        if auth.get('type')!='auth' or auth.get('access_token')!='fixture-only':return
        send(c,{'type':'auth_ok','ha_version':'fixture'})
        subscription=None; state='off'; reads=0
        while True:
            m=read(c); kind=m['type']; id=m['id']; result=None;success=True
            record(kind)
            if kind=='subscribe_events':subscription=id
            elif kind=='get_states':
                reads+=1
                snapshot=state
                if reads==1:
                    state='on'
                    send(c,{'id':subscription,'type':'event','event':{'event_type':'state_changed','data':{'entity_id':'light.desk','new_state':entity('light.desk',state,'Desk lamp')}}})
                result=[entity('light.desk',snapshot,'Desk lamp'),entity('switch.fan','off','Desk fan'),entity('sensor.temperature','22.4','Room temperature',{'unit_of_measurement':'°C','device_class':'temperature'}),entity('scene.evening','unknown','Evening'),entity('light.missing','unavailable','Offline light'),entity('lock.front','locked','Front door')]
            elif kind=='get_services':result={d:{'turn_on':{},'turn_off':{}} for d in ['light','switch','scene']}
            elif kind=='get_config':result={'location_name':'Fixture Home'}
            elif kind=='config/area_registry/list':result=[{'area_id':'office','name':'Office'}]
            elif kind=='config/device_registry/list':result=[]
            elif kind=='config/entity_registry/list':result=[{'entity_id':e,'area_id':'office'} for e in ['light.desk','switch.fan','sensor.temperature']]
            elif kind=='call_service':
                if mode=='disconnect_after_write':return
                if mode!='unchanged':state='on' if m['service']=='turn_on' else 'off'
                result={'context':{'id':'fixture-result'}}
            elif kind=='ping':send(c,{'id':id,'type':'pong'});continue
            if mode=='rooms_denied' and kind.startswith('config/'):success=False
            send(c,{'id':id,'type':'result','success':success,'result':result})
    except (EOFError,ConnectionError,OSError,ValueError,KeyError):pass
    finally:c.close()
while True:
    c,_=server.accept();threading.Thread(target=handle,args=(c,),daemon=True).start()

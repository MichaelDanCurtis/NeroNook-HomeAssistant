"""Fixed TCP relay exposing only the isolated virtual HA to Mac loopback.
No request parsing, dynamic destinations, logging, credentials or device access.
"""
import selectors,socket,threading

def relay(client):
    upstream=None
    try:
        upstream=socket.create_connection(('homeassistant',8123),timeout=10)
        client.settimeout(30);upstream.settimeout(30)
        pairs={client:upstream,upstream:client}
        with selectors.DefaultSelector() as selector:
            for peer in pairs:selector.register(peer,selectors.EVENT_READ)
            while True:
                events=selector.select(300)
                if not events:return
                for key,_ in events:
                    data=key.fileobj.recv(65536)
                    if not data:return
                    pairs[key.fileobj].sendall(data)
    except (OSError,TimeoutError):pass
    finally:
        client.close()
        if upstream:upstream.close()
server=socket.socket();server.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
server.bind(('0.0.0.0',8123));server.listen(16)
while True:
    client,_=server.accept();threading.Thread(target=relay,args=(client,),daemon=True).start()

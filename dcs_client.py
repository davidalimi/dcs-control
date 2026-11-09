import socket
import threading
import time

HOST, PORT = "127.0.0.1", 7777
s = None  # current connection, None while disconnected

def _watch():
    """Background thread: connect, wait until the link drops, reconnect."""
    global s
    waiting_printed = False
    while True:
        try:
            conn = socket.create_connection((HOST, PORT), timeout=2)
            conn.settimeout(None)
        except OSError:
            if not waiting_printed:
                print("[dcs] waiting for DCS mission...")
                waiting_printed = True
            time.sleep(2)
            continue

        s = conn
        waiting_printed = False
        print("[dcs] connected")
        try:
            while conn.recv(1024):   # DCS never sends data; recv returns b"" when it closes
                pass
        except OSError:
            pass
        s = None
        conn.close()
        print("[dcs] connection lost, reconnecting...")


def lua(code: str):
    # Allow readable multi-line Lua: drop full-line comments, join the rest into one line
    code = " ".join(
        l.strip() for l in code.splitlines()
        if l.strip() and not l.strip().startswith("--")
    )
    if s is None:
        print("[dcs] not connected, command not sent")
        return
    try:
        s.sendall(code.encode() + b"\n")   # one line per command
    except OSError:
        print("[dcs] send failed, command not sent")


threading.Thread(target=_watch, daemon=True).start()
time.sleep(0.5)   # give the first connection a moment
#!/usr/bin/env python3
"""Task-local adapter for the two Claude 2.1.325 sandbox socat modes only."""
import re
import selectors
import socket
import sys
import threading


def endpoints(args):
    if len(args) != 2:
        raise ValueError("expected exactly two sandbox relay endpoints")
    source, target = args
    unix = re.fullmatch(r"UNIX-LISTEN:([^,]+),fork,reuseaddr", source)
    tcp = re.fullmatch(r"TCP:localhost:([0-9]+),keepalive,keepidle=10,keepintvl=5,keepcnt=3", target)
    if unix and tcp:
        return socket.AF_UNIX, unix[1], socket.AF_INET, ("127.0.0.1", port(tcp[1]))
    tcp = re.fullmatch(r"TCP([46])-LISTEN:([0-9]+),(ipv6only=0,)?fork,reuseaddr,backlog=4096", source)
    unix = re.fullmatch(r"UNIX-CONNECT:([^,]+)", target)
    if tcp and unix and ((tcp[1] == "6") == bool(tcp[3])):
        family = socket.AF_INET6 if tcp[1] == "6" else socket.AF_INET
        host = "::" if family == socket.AF_INET6 else "0.0.0.0"
        return family, (host, port(tcp[2])), socket.AF_UNIX, unix[1]
    raise ValueError("unsupported sandbox relay arguments")


def port(value):
    result = int(value)
    if not 0 < result < 65536:
        raise ValueError("port outside 1..65535")
    return result


def relay(client, target_family, target):
    with client, socket.socket(target_family, socket.SOCK_STREAM) as remote:
        try:
            remote.connect(target)
            with selectors.DefaultSelector() as ready:
                ready.register(client, selectors.EVENT_READ, remote)
                ready.register(remote, selectors.EVENT_READ, client)
                while ready.get_map():
                    for key, _ in ready.select():
                        data = key.fileobj.recv(65536)
                        if data:
                            key.data.sendall(data)
                        else:
                            ready.unregister(key.fileobj)
                            key.data.shutdown(socket.SHUT_WR)
        except OSError as exc:
            print(f"sandbox-relay: connection failed: {exc}", file=sys.stderr)


def main(args):
    try:
        family, source, target_family, target = endpoints(args)
        with socket.socket(family, socket.SOCK_STREAM) as listener:
            if family != socket.AF_UNIX:
                listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if family == socket.AF_INET6:
                listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            listener.bind(source)
            listener.listen(4096)
            while True:
                client, _ = listener.accept()
                threading.Thread(target=relay, args=(client, target_family, target), daemon=True).start()
    except (OSError, ValueError) as exc:
        print(f"sandbox-relay: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

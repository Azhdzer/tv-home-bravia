#!/usr/bin/env python3
"""Tiny ADB-over-Wi-Fi client (no adb binary or Android platform-tools needed).

    tv.py --probe                            (TV_HOST env or tools/.tv_host)
    tv.py "pm list packages"                 one shell command
    tv.py --batch < cmds.txt                 one command per line, same connection
    tv.py --pull /sdcard/x.png x.png
    tv.py --push-b64 local.apk /data/local/tmp/x.apk   chunked base64 upload with md5 check
    tv.py --shot out.png                     screenshot from the TV
"""
import base64
import hashlib
import os
import socket
import sys
import time

from adb_shell.adb_device import AdbDeviceTcp
from adb_shell.auth.keygen import keygen
from adb_shell.auth.sign_pythonrsa import PythonRSASigner
from adb_shell.exceptions import AdbTimeoutError, DeviceAuthError

# A Russian Windows console can't encode everything a TV prints; don't crash on it.
sys.stdout.reconfigure(errors="replace")
sys.stderr.reconfigure(errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
HOST_FILE = os.path.join(HERE, ".tv_host")  # written by find-tv.ps1, git-ignored
HOST = os.environ.get("TV_HOST") or (open(HOST_FILE, encoding="utf-8-sig").read().strip() if os.path.exists(HOST_FILE) else "")
if not HOST:
    sys.exit("IP телевизора неизвестен. Запустите tools\\find-tv.ps1 или задайте: tools\\find-tv.ps1 -Ip 192.168.x.y")
PORT = int(os.environ.get("TV_PORT", "5555"))
KEY = os.path.join(HERE, "adbkey", "adbkey")


def signer():
    os.makedirs(os.path.dirname(KEY), exist_ok=True)
    if not os.path.exists(KEY):
        keygen(KEY)
    return PythonRSASigner(open(KEY + ".pub").read(), open(KEY).read())


def no_connection(error):
    return (f"Нет связи с ТВ {HOST}:{PORT} ({error}). ТВ включён и в той же сети? В настройках для разработчиков "
            "включена отладка по USB? Если IP поменялся, запустите tools\\find-tv.ps1.")


def connect():
    # A TV on Wi-Fi can drop the odd connection; that shouldn't stop a script halfway through.
    error = None
    for _ in range(3):
        dev = AdbDeviceTcp(HOST, PORT, default_transport_timeout_s=120.0)
        try:
            dev.connect(rsa_keys=[signer()], auth_timeout_s=120)
            return dev
        except (DeviceAuthError, AdbTimeoutError) as e:
            sys.exit(f"ТВ {HOST}:{PORT} не разрешил подключение ({e}). "
                     "Подтвердите на экране ТВ «Разрешить отладку» и повторите.")
        except socket.timeout as e:
            sys.exit(no_connection(e))
        except Exception as e:
            error = e
            time.sleep(1)
    sys.exit(no_connection(error))


def push_b64(dev, local, remote, chunk=48_000):
    data = open(local, "rb").read()
    enc = base64.b64encode(data).decode()
    tmp = remote + ".b64"
    # The whole shell command has to fit in one ADB packet, and that limit varies per TV.
    chunk = min(chunk, dev.max_chunk_size - 128)
    dev.shell(f"rm -f {tmp} {remote}")
    for i in range(0, len(enc), chunk):
        dev.shell(f"echo -n '{enc[i:i + chunk]}' >> {tmp}")
    dev.shell(f"base64 -d {tmp} > {remote} && rm -f {tmp}")
    remote_md5 = dev.shell(f"md5sum {remote}").split()[0]
    local_md5 = hashlib.md5(data).hexdigest()
    if remote_md5 != local_md5:
        sys.exit(f"md5 mismatch: {remote_md5} != {local_md5}")
    print(f"pushed {local} -> {remote} ({len(data)} bytes, md5 ok)")


def main():
    a = sys.argv[1:]
    dev = connect()
    if not a or a == ["--probe"]:
        for p in ("ro.product.manufacturer", "ro.product.brand", "ro.product.model", "ro.product.device",
                  "ro.build.version.release", "ro.build.version.sdk", "ro.build.display.id"):
            print(f"{p} = {dev.shell(f'getprop {p}').strip()}")
    elif a[0] == "--batch":
        # utf-8-sig: PowerShell can prepend a BOM when piping, which would corrupt the first command.
        for line in sys.stdin.buffer.read().decode("utf-8-sig", errors="replace").splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                print(f"$ {line}\n{dev.shell(line, read_timeout_s=120).rstrip()}")
    elif a[0] == "--pull":
        dev.pull(a[1], a[2])
    elif a[0] == "--push-b64":
        push_b64(dev, a[1], a[2])
    elif a[0] == "--shot":
        dev.shell("screencap -p /sdcard/_shot.png")
        dev.pull("/sdcard/_shot.png", a[1])
        dev.shell("rm /sdcard/_shot.png")
        print(f"saved {a[1]}")
    else:
        print(dev.shell(" ".join(a), read_timeout_s=120).rstrip())
    dev.close()


if __name__ == "__main__":
    main()

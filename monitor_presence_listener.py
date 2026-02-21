import argparse
import ctypes
import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path
import socket
import threading
import time
from ctypes import wintypes

BROADCAST_PORT = 4210
DATA_PORT = 4211

PRESENCE_THRESHOLD_CM = 80
AWAY_HOLD_SECONDS = 4.0
PACKET_TIMEOUT_SECONDS = 2.0
PRESENT_SAMPLES_REQUIRED = 2
SENSOR_OFFLINE_GRACE_SECONDS = 20.0
BROADCAST_INTERVAL_SECONDS = 5.0
SOCKET_TIMEOUT_SECONDS = 0.5
DEBUG_DISTANCE_LOG = False

BASE_DIR = Path(__file__).resolve().parent
LOG_FILE = BASE_DIR / "listener.log"

HWND_BROADCAST = 0xFFFF
WM_SYSCOMMAND = 0x0112
SC_MONITORPOWER = 0xF170
SMTO_ABORTIFHUNG = 0x0002
INPUT_MOUSE = 0
MOUSEEVENTF_MOVE = 0x0001
KEYEVENTF_KEYUP = 0x0002
VK_SHIFT = 0x10
BELOW_NORMAL_PRIORITY_CLASS = 0x00004000

# Create UDP socket
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("", DATA_PORT))

user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx", wintypes.LONG),
        ("dy", wintypes.LONG),
        ("mouseData", wintypes.DWORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
    ]


class INPUT(ctypes.Structure):
    class _INPUT_UNION(ctypes.Union):
        _fields_ = [("mi", MOUSEINPUT)]

    _anonymous_ = ("union",)
    _fields_ = [("type", wintypes.DWORD), ("union", _INPUT_UNION)]

monitor_off = False
away_since = None
present_samples = 0
last_packet_time = time.monotonic()
sensor_online = False


logger = logging.getLogger("esp32_monitor_listener")


def setup_logging(background_mode=False):
    logger.setLevel(logging.INFO)
    logger.handlers.clear()

    file_handler = RotatingFileHandler(LOG_FILE, maxBytes=512_000, backupCount=2, encoding="utf-8")
    file_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    logger.addHandler(file_handler)

    if not background_mode:
        stream_handler = logging.StreamHandler()
        stream_handler.setFormatter(logging.Formatter("%(message)s"))
        logger.addHandler(stream_handler)


def set_low_priority():
    try:
        process = kernel32.GetCurrentProcess()
        kernel32.SetPriorityClass(process, BELOW_NORMAL_PRIORITY_CLASS)
    except Exception:
        logger.warning("Could not set process priority")


def turn_monitors_off():
    send_monitor_power(2)


def turn_monitors_on():
    send_monitor_power(-1)

    input_event = INPUT()
    input_event.type = INPUT_MOUSE
    input_event.mi = MOUSEINPUT(1, 0, 0, MOUSEEVENTF_MOVE, 0, None)
    user32.SendInput(1, ctypes.byref(input_event), ctypes.sizeof(INPUT))

    user32.keybd_event(VK_SHIFT, 0, 0, 0)
    user32.keybd_event(VK_SHIFT, 0, KEYEVENTF_KEYUP, 0)


def send_monitor_power(state):
    ok = user32.SendMessageTimeoutW(
        HWND_BROADCAST,
        WM_SYSCOMMAND,
        SC_MONITORPOWER,
        state,
        SMTO_ABORTIFHUNG,
        250,
        None,
    )
    if not ok:
        user32.PostMessageW(HWND_BROADCAST, WM_SYSCOMMAND, SC_MONITORPOWER, state)


def mark_sensor_online():
    global sensor_online
    if not sensor_online:
        sensor_online = True
        logger.info("ESP32 sensor online")


def handle_sensor_offline_failsafe(elapsed_since_packet):
    global sensor_online, monitor_off, away_since, present_samples

    if elapsed_since_packet < SENSOR_OFFLINE_GRACE_SECONDS:
        return False

    if sensor_online:
        sensor_online = False
        logger.warning("ESP32 sensor offline (no packets) - fail-safe active")

    away_since = None
    present_samples = 0
    if monitor_off:
        turn_monitors_on()
        monitor_off = False
        logger.info("Fail-safe: monitors ON")
    return True


def update_presence_from_distance(distance):
    global monitor_off, away_since, present_samples

    now = time.monotonic()
    in_range = 0 < distance <= PRESENCE_THRESHOLD_CM

    if in_range:
        present_samples += 1
        away_since = None
        if monitor_off and present_samples >= PRESENT_SAMPLES_REQUIRED:
            turn_monitors_on()
            monitor_off = False
            logger.info("🟢 User back -> monitors ON")
    else:
        present_samples = 0
        if away_since is None:
            away_since = now
        if not monitor_off and (now - away_since) >= AWAY_HOLD_SECONDS:
            turn_monitors_off()
            monitor_off = True
            logger.info("⚫ User away -> monitors OFF")


def update_presence_from_timeout():
    global monitor_off, away_since, present_samples

    now = time.monotonic()
    elapsed = now - last_packet_time

    if handle_sensor_offline_failsafe(elapsed):
        return

    if elapsed <= PACKET_TIMEOUT_SECONDS:
        return

    present_samples = 0
    away_since = None

def broadcast_presence():
    broadcast_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    broadcast_sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

    while True:
        try:
            broadcast_sock.sendto(b"PC_ONLINE", ("<broadcast>", BROADCAST_PORT))
        except Exception as exc:
            logger.warning(f"Broadcast error: {exc}")
        time.sleep(BROADCAST_INTERVAL_SECONDS)

def listen_for_data():
    global last_packet_time
    logger.info("Listening for ESP32...")
    while True:
        try:
            sock.settimeout(SOCKET_TIMEOUT_SECONDS)
            try:
                data, addr = sock.recvfrom(1024)
            except socket.timeout:
                update_presence_from_timeout()
                continue

            last_packet_time = time.monotonic()
            mark_sensor_online()
            message = data.decode(errors="ignore").strip()

            if not message.startswith("DIST:"):
                continue

            raw_distance = message.split(":", 1)[1]
            try:
                distance = int(raw_distance)
            except ValueError:
                continue

            if DEBUG_DISTANCE_LOG:
                logger.info(f"Distance: {distance} cm")
            update_presence_from_distance(distance)
        except Exception as exc:
            logger.exception(f"Listener error: {exc}")
            time.sleep(0.2)


def parse_args():
    parser = argparse.ArgumentParser(description="ESP32 monitor auto turnoff listener")
    parser.add_argument("--background", action="store_true", help="Run with file logging only")
    return parser.parse_args()


def main():
    args = parse_args()
    setup_logging(background_mode=args.background)
    set_low_priority()

    threading.Thread(target=broadcast_presence, daemon=True).start()
    listen_for_data()


if __name__ == "__main__":
    main()
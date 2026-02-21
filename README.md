# ESP32 Monitor Auto Turnoff

An ESP32 + HC-SR04 based presence detector that turns PC displays off when the user is away and restores display output when the user returns.

This is a custom implementation designed to mirror the auto turn-off behavior found in modern OLED monitor care features.

This project uses:
- `ESP32MonitorAutoTurnoff.ino` on the ESP32 for distance sensing + UDP telemetry
- `monitor_presence_listener.py` on Windows for monitor power control and runtime fail-safe handling

## Features

- Presence detection based on distance threshold
- Display off when user is away (no sleep/hibernate)
- Display restore when user returns
- Sensor offline fail-safe (forces displays on)
- Low process priority to minimize system impact
- Startup automation scripts for Windows login
- Status and uninstall scripts

## Hardware

- ESP32 development board
- HC-SR04 ultrasonic distance sensor
- Breadboard and jumper wires
- Resistors for ECHO voltage divider:
  - one 2k resistor from ECHO to junction
  - two 2k resistors in series from junction to GND

## Wiring

### Complete Wiring (All Pins)

1. **VCC**
   - HC-SR04 VCC -> ESP32 5V or VIN
   - Use the 5V pin (not 3.3V)

2. **GND**
   - HC-SR04 GND -> breadboard GND rail
   - ESP32 GND -> same GND rail
   - All grounds must be connected together

3. **TRIG**
   - HC-SR04 TRIG -> ESP32 GPIO 5
   - No resistor required

4. **ECHO (with voltage divider)**
   - HC-SR04 ECHO -> 2k resistor -> junction point
   - From junction:
     - wire -> ESP32 GPIO 18
     - two 2k resistors in series -> GND rail

### Final Pin Summary

| Sensor Pin | Connection |
|---|---|
| VCC | ESP32 5V |
| GND | Shared GND rail |
| TRIG | GPIO 5 |
| ECHO | Voltage divider -> GPIO 18 |

## Network Flow

- PC broadcasts `PC_ONLINE` over UDP on port `4210`
- ESP32 receives handshake and sends `DIST:<cm>` to PC on UDP port `4211`
- Listener applies away/present state machine and controls display power

## Software Requirements

- Windows 10/11
- Python 3.9+
- Arduino IDE (or equivalent) for ESP32 firmware upload
- ESP32 connected to same LAN/Wi-Fi as the PC

## Setup

1. Copy `credentials_template.h` to `credentials.h` and update with your Wi-Fi SSID and password.
2. Upload `ESP32MonitorAutoTurnoff.ino` to ESP32.
3. Run listener manually for testing:

```powershell
python monitor_presence_listener.py
```

4. Install auto-start at login:

```powershell
powershell -ExecutionPolicy Bypass -File .\install_monitor_listener_autostart.ps1
```

5. Check runtime status:

```powershell
powershell -ExecutionPolicy Bypass -File .\monitor_listener_status.ps1 -NoPause
```

6. Remove auto-start and stop running listener:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall_monitor_listener_autostart.ps1
```

## Configuration

Edit constants in `monitor_presence_listener.py`:

- `PRESENCE_THRESHOLD_CM`
- `AWAY_HOLD_SECONDS`
- `PACKET_TIMEOUT_SECONDS`
- `PRESENT_SAMPLES_REQUIRED`
- `SENSOR_OFFLINE_GRACE_SECONDS`

## Performance Notes

- UDP messages are small and low-rate; network overhead is minimal.
- Listener process runs at below-normal CPU priority.
- Design is intended to avoid noticeable impact on gaming or normal desktop use.

## Logging

Runtime logs are written to:

- `listener.log`

Use `monitor_listener_status.ps1` to print the latest log lines.

## Repository Files

- `ESP32MonitorAutoTurnoff.ino` - ESP32 firmware
- `credentials_template.h` - Wi-Fi credentials template (copy to credentials.h)
- `monitor_presence_listener.py` - Windows listener and monitor control
- `install_monitor_listener_autostart.ps1` - install autostart (Task Scheduler or Startup fallback)
- `uninstall_monitor_listener_autostart.ps1` - remove autostart and stop running listener
- `monitor_listener_status.ps1` - quick status and log summary

## License

This project is licensed for personal, non-commercial use only. Commercial use and selling are not permitted. See [LICENSE](./LICENSE.md).

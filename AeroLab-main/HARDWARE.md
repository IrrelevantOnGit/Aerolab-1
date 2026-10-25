# AeroLab rig: hardware audit & wiring checklist

Derived from the pin map in `main.cpp`. Items marked **CHECK** depend on the exact modules you bought.

## Likely failure points (fix these first)
| # | Issue | Why it matters | Fix |
|---|-------|----------------|-----|
| 1 | **HC-SR04 ECHO is 5 V** (GPIO 18, 23) | ESP32 GPIOs are 3.3 V only; 5 V on ECHO can overstress the pin | Use a proper 5 V→3.3 V level shifter or a 3.3 V-compatible module. One divider example for nominal 5 V ECHO is **1 kΩ series (ECHO→GPIO node) + 1.5 kΩ (node→GND)**, producing ~3.0 V; verify module maximum voltage, resistor tolerances, and ESP32 input limits. **Do not use the former 1 kΩ + 2 kΩ values**, which produce ~3.33 V nominal. Verify actual wiring before powering. **CHECK** |
| 2 | **GPIO 39 button has no pull-up** (`INPUT`) | GPIO 34-39 are input-only with no internal pulls; a floating pin gives phantom mode changes (firmware's baseline trick only hides it) | 10 kΩ to 3V3, button to GND |
| 3 | **MQ-135 / MQ-2 AO can swing to ~5 V** (GPIO 32, 35) | Over-voltage on ADC1; readings clip near 3.1 V at 11 dB so `>3200` trips are unreachable | Divider 10 kΩ/20 kΩ on each AO. **CHECK** module output range |
| 4 | **MQ heaters need 5 V, ~150 mA each**, 24-48 h burn-in, 20 s+ warm-up per power-up | Gas thresholds are meaningless while cold | Power from 5 V rail, not 3V3; ignore gas alarms for first 60 s |
| 5 | **SG90 stall ≈ 650 mA** on GPIO 13 | Shared USB/regulator rail → brown-outs, random resets, OLED glitches | Separate 5 V ≥ 1 A supply, **common GND**, 470-1000 µF across servo supply |
| 6 | **Buzzer type** | `playTone()` bit-bangs a frequency; an *active* buzzer ignores it (one fixed pitch) | Use a **passive** piezo for per-mode pitches; drive via 1 kΩ or NPN |
| 7 | **Servo ultrasonic (US2) close-range return needs commissioning** | A stable fresh echo near 3.9 cm is not enough to distinguish a real nearby object from mount/cross-talk/echo artifacts | Verify exact module marking and its datasheet; remove nearby reflecting parts; ensure US1/US2 are separated and not facing each other; test targets at 5, 10, 20, 50 cm at several servo angles. Current 2 cm lower software bound is only the nominal HC-SR04-class specification, not verified for the installed module. Do not mute/disable a critical alarm to hide a close return |
| 8 | **LDR thresholds are not calibrated** | ADC counts depend on divider orientation, ambient light, and sensor placement | Record ADC at installed position in normal light, hand shadow, and fully covered states before enabling yellow/red thresholds. Current firmware reports raw ADC only; `ldrCalibrated=0` |

## Pin map (as coded)
| Signal | GPIO | Notes |
|---|---|---|
| DHT11 | 4 | 10 kΩ pull-up to 3V3 (most modules include it); firmware reads ≤ 0.5 Hz effective |
| US#1 TRIG / ECHO | 5 / 18 | Fixed/bench sensor. GPIO 5 is a strapping pin: don't hold it low/high at reset |
| US#2 TRIG / ECHO | 19 / 23 | Servo-mounted scan sensor. Use flexible wire, keep ≥ 5 cm from US#1 to avoid cross-talk |
| Servo | 13 | 500-2400 µs, 50 Hz |
| LDR | 34 | ADC1, input-only: divider with 10 kΩ |
| MQ-135 / MQ-2 | 32 / 35 | ADC1 (safe with Wi-Fi); see #3 |
| Buzzer | 25 | |
| LEDs R / G / Y | 26 / 27 / 14 | 220-330 Ω each. GPIO 14 pulses at boot, so a brief yellow blink is normal |
| Buttons | 2 / 39 / 0 | GPIO 0 = BOOT (don't hold at reset), GPIO 2 = strapping + onboard LED |
| I²C SDA / SCL | 21 / 22 | OLED 0x3C, MPU-6050 0x68, 4.7 kΩ pull-ups (modules usually include) |

### Ultrasonic commissioning protocol
1. Record the exact module markings (HC-SR04, HC-SR04P, or other) and use its own minimum-range specification; the nominal 2 cm code limit is not evidence the fitted sensor meets that value.
2. With the servo at 90°, leave a clear corridor and log at least 100 raw echoes. A persistent value around 3.9 cm is a **critical-range observation**, not a software-cleared fault; inspect transducer orientation, the horn/bracket, wiring/cross-talk, and reflectors.
3. Put a flat target in front at measured 5, 10, 20, and 50 cm. Repeat at 45°, 90°, and 135° with the same target orientation. Log raw value, filtered value, echo age, servo angle, and alarm state.
4. Repeat the clear-space test at those angles. Only after the clear-space returns separate from target returns should scan/tracking thresholds or a sensor-specific exclusion be changed. Save the CSV and calibration result.

The firmware reports per-acquisition `us1Diagnostic` / `us2Diagnostic` plus `us1PulseUs` / `us2PulseUs`: code 0 means no ECHO pulse before timeout, 1 is an accepted 2–200 cm return, 2 is below the configured near limit, 3 is outside the configured range, and 4 indicates manual HIL override. The 200 cm ceiling leaves margin below the 12 ms timeout's theoretical distance (~206 cm) and matches the live scope axis. Values from 75–200 cm are valid clear-space measurements, not sensor failures; the earlier 75 cm software ceiling incorrectly marked farther room surfaces as missing data. These diagnostics separate timeout from rejected-distance samples, but do not identify physical wiring causes by themselves.

## Power budget (worst case, 5 V rail)
ESP32 + Wi-Fi ~240 mA · SG90 stall ~650 mA · 2× MQ heaters ~300 mA · 2× HC-SR04 ~30 mA · OLED/MPU/LEDs ~60 mA → **≈ 1.3 A**. A USB port (500 mA) is not enough: use a 5 V / 2 A supply.

## Bring-up order
1. Power with servo/MQ disconnected, confirm 3.3 V rail and the OLED boot screen.
2. Add I²C devices; the serial log should report MPU/OLED found.
3. Add ultrasonics (with dividers), then LDR/MQ, then servo on its own supply.
4. Flash once over USB; afterwards `pio run -e ota -t upload` (hostname `aerolab.local`).
5. In the dashboard press **Record**, run Mode 4 (step test), and keep the CSV as your evidence.

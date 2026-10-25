# AeroLab faculty demo runbook

## Before the demo

1. Power the ESP32 and sensor rig from a safe bench supply. Keep propellers off, keep hands clear of the servo horn, and do not power a stalled servo from the ESP32 3.3 V rail.
2. Start `start_bridge.bat` once. Open the main `dashboard.html` in Edge or Chrome.
3. For a hardware run, connect the laptop to the `AeroLab-Avionics` access point (or select the board's USB serial port in the dashboard). The laptop currently has to be on the board's network for Wi-Fi telemetry; `192.168.4.1` will not respond while the laptop is on a different network.
4. Leave **HIL SENSOR OVERRIDE** off. Connect **WIFI** or **USB** and verify that firmware packets and values update. Report transport and sensor health separately: a working USB/bridge link does not prove both ultrasonic channels work. Before claiming dual-sensor operation, confirm that both `us1EchoOk` and `us2EchoOk` are fresh and each distance changes plausibly with a measured target. A green-looking UI alone is not proof of sensor health.
5. Click **PYTHON SCOPE** and **MATLAB** once each. Confirm each titled figure appears; the bridge restores/focuses an existing scope instead of silently claiming success. A live-only scope that says “STALE / DISCONNECTED” is waiting for hardware and has no substitute data.

## Reliable fallback when the board stream is unavailable

Click **DEMO first**, then launch the Python and MATLAB scopes. The scopes now receive the explicit demo selection and generate labeled illustrative plots. If a Python scope was already open in live-only mode, close that figure once and click Python Scope again while DEMO is selected. Keep the “SIMULATION ONLY” banner visible during the presentation; do not describe these traces or CSV rows as measured hardware results.

## Five-minute story for the professor

- **Problem:** demonstrate an embedded sensor/control dashboard with a sampled control model, observer, residual monitor, and an ESP32 telemetry path.
- **Architecture:** sensors → firmware sampling and control → JSON telemetry over USB/Wi-Fi → dashboard and Python/MATLAB viewers. The MATLAB model provides design/simulation evidence; it is not an independently identified physical twin.
- **Graph 1 — model states:** firmware internal state, observer estimate, and twin-model output. These are related software states, not an independent measurement of actuator position.
- **Graph 2 — residual and CUSUM:** residual threshold `δ = 0.100`; one-sided CUSUM threshold `h = 0.060`. The axes are independent and the plotted thresholds are in their respective units. A demo fault is software-injected.
- **Graph 3 — control/servo:** normalized control effort and servo position divided by 180. This is a command/position report, not external torque or motor feedback.
- **Graph 4 — attitude/range:** IMU roll/pitch and ultrasonic range are displayed on separate scales.
- **Takeaway:** the project integrates embedded telemetry, model-based control/monitoring, and multiple visualization paths; its current quantitative control and detector evidence is simulation/software evidence.

## Claims to keep precise

- The ESP32 AP is `AeroLab-Avionics` at `192.168.4.1`; the PC must join that AP for the direct Wi-Fi route. USB telemetry is configured at 460800 baud on CP210x COM14. During the latest check, the local bridge was connected to COM14 and receiving fresh `ESP32_FIRMWARE` packets; both MATLAB and Python scope windows were visible. This verifies the transport and scope launch state at that moment, not continuous uptime or calibrated measurements.
- Across two live snapshots, US1 produced fresh accepted readings of about 149.5 cm and later 42.2 cm. US2 produced no echo (0 μs; over 18 minutes without a fresh return at the latest read); its retained 3.88 cm raw sample was stale, not a current obstacle. The dashboard correctly showed `RANGE UNKNOWN: US1 FRESH, US2 NO FRESH ECHO`. US2 and hand-sector detection are **unresolved and not verified**. Do not describe both sensors as working until a known-distance target test confirms fresh responses from both.
- The LDR is raw ADC and `ldrCalibrated=0`; firmware intentionally does not issue light-based yellow/red alarms until its installed light-divider polarity and baseline are calibrated. Do not claim calibrated photometric thresholds.
- The hand mode uses one servo-mounted ultrasonic sensor to scan and lock to a detected range sector. It is not camera-based or continuous 2-D hand-pose tracking.
- Two range sensors can trigger proximity caution/critical states independently when both return valid fresh echoes; `NO ECHO` is a sensor fault, not a clear path.
- The host C++ test has not been run because no host C++ compiler is installed. Firmware build, Python self-test, MATLAB simulation, and dashboard script checks are software checks only.

## If something misbehaves live

- **No changing values:** verify the laptop is on the board AP or that the correct USB serial port is selected; check HIL override is off; wait for packet freshness and echo-health flags.
- **Scopes do not appear:** click the button once, wait up to 15 seconds, then click once more to restore/focus. Do not start multiple copies of MATLAB. Read the event log/startup log if still absent.
- **Only blank scope axes:** a live-only scope has no fresh packet for the plotted signal. Either restore the hardware link or deliberately switch the dashboard to DEMO, then reopen the scope. A fresh bridge packet can coexist with a missing US2 range; it does not validate US2.
- **US2 / hand mode:** check the module supply and common ground, flexible servo-cable continuity, GPIO 19 TRIG / GPIO 23 ECHO routing, and a verified ECHO level shifter for any 5 V module. Clear nearby reflectors and test flat targets at measured 5, 10, 20, and 50 cm with the servo at multiple angles. Keep the range-unknown warning visible until fresh readings are observed; do not silence it or call a stale 3.88 cm sample live.
- **Hand/alarm or light response differs:** show the reported raw range/ADC and sensor-health fields; do not tune thresholds on the fly or override the sensor and call it a measurement.
- **CSV:** press REC only after verifying the desired source. Keep the `source` field; it distinguishes `LIVE_HARDWARE` from `SIMULATION_ONLY`.

## One-line conclusion

“AeroLab is a working software-and-firmware demonstrator for sampled control, telemetry visualization, and model-residual monitoring; the plots shown are explicitly separated into live hardware telemetry or labeled simulation, and the physical sensor calibrations remain a follow-up validation step.”

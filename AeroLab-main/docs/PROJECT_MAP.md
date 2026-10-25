# Project map and evidence status

## Active files

| Area | Canonical files | Purpose |
|---|---|---|
| Firmware | `main.cpp`, `gnc_core.h`, `gnc_gains.h`, `platformio.ini`, `test/host_control_test.cpp` | ESP32 application, saturated controller helper, generated gains, build configuration, host control test |
| Model | `control_simulation.m` | Assumed second-order model, LQR/observer design, sampled simulation, injected-fault study, figure and gain export |
| Exploration | `notebooks/control_systems_digital_twin.ipynb` | Exploratory notebook; not required by firmware/dashboard runtime |
| Dashboard | `dashboard.html`, `dashboard_analytics.html`, `vendor/three.min.js` | Main and analytics web UIs plus runtime WebGL library |
| Scopes/bridge | `python_realtime_scope.py`, `live_python_scope.py`, `matlab_realtime_scope.m`, `matlab_bridge.py`, launch/start batch files | Python/MATLAB scope processes and local telemetry relay |
| Hardware | `HARDWARE.md`, `wifi_secrets.h` | Wiring and hardware setup; local network configuration (do not publish secrets) |
| Results | `results/figures/`, `results/verification/` | Generated figures and test/render artifacts |
| Research | `research/references/` | Source paper and its executive brief |
| Deliverables | `deliverables/paper/`, `deliverables/faculty/` | Current editable working manuscript and faculty walkthrough |
| Archive | `archive/` | Superseded, duplicate, diagnostic, or stale files retained for recovery/reference |

## Evidence boundaries

- `control_simulation.m` sets ωₙ=89 rad/s and ζ=0.45 as model values; no identification dataset/procedure is included.
- MATLAB step response, observer, residual/CUSUM, and parameter sweeps are software simulation evidence.
- Firmware `y_measured` comes from internal model state plus modeled disturbance/drift; `x1_real` and `x1_t` use the same model matrices and command. This residual is not independent physical actuator feedback.
- `gnc_gains.h` is generated from MATLAB and should not be manually edited.
- The board's physical sensors (including LDR) are distinct telemetry channels. LDR is raw/uncalibrated. One servo range sensor supports angular-sector scanning, not continuous 2-D hand tracking.
- A 20 Hz configured control interval does not establish observed packet rate or jitter. Use timestamps and logs.
- Python `--selftest` checks a deterministic synthetic detector/plot path only.
- Post-repair live checks observed fresh dual-channel ranging and US2 yellow/red/green target response; US1 close-range red/clear recovery was observed, but sustained US1 yellow and calibrated distance accuracy remain unverified. A later Mode-5 sample showed intermittent US2 freshness; see the dated verification record before making a repeatability claim.
- Mode 5 is the IMU gimbal mode (servo near 90°); Mode 1 is the servo-mounted US2 sector scan. Do not present Mode-5 scope data as a hand-tracking test.
- `results/verification/verification-record.md` records the most recent reproducible software checks and what remains unverified.

## Cleanup policy

Root files are kept to the active runtime, firmware, source model, and entry-point documentation. Results and figures go under `results/`; current paper and presentation artifacts stay in `deliverables/`; prior documents, alternate dashboard/notebook copies, screenshots, and diagnostics are retained under `archive/`. Do not delete archived files until the project owner confirms they are unnecessary.

## Current deliverables

- `deliverables/paper/AeroLab_IEEE_Style_Manuscript.docx` and `.pdf` — six-page IEEE Access-template manuscript; distinguishes model/simulation results from bounded post-repair live observations and documents intermittent echo freshness.
- `deliverables/faculty/AeroLab_Faculty_Demo_Guide_current.docx` — faculty narrative and graph interpretation.
- `build_faculty_deliverables.py` — reproducible document source builder.

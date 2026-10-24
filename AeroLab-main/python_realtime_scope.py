"""
AeroLab REAL-TIME SCOPE (Python) - instant backup for MATLAB.   Needs: numpy, matplotlib  (pyserial optional)
  python python_realtime_scope.py                 live bridge; waits for data without synthetic substitution
  python python_realtime_scope.py --source demo   force demo (no hardware)
  python python_realtime_scope.py --source usb --port COM14
  python python_realtime_scope.py --selftest      render 3 s headless to scope_selftest.png
"""
import argparse, collections, json, math, sys, time, urllib.request
import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("--source", default="auto", choices=["auto", "bridge", "wifi", "usb", "demo"])
ap.add_argument("--port", default="COM14")
ap.add_argument("--window", type=float, default=25.0)
ap.add_argument("--selftest", action="store_true")
args = ap.parse_args()
if args.source == "auto" or args.source in ("wifi", "usb"):
    pass
import matplotlib
if args.selftest:
    matplotlib.use("Agg")
else:
    # Select a GUI backend explicitly before pyplot import. If no usable GUI
    # backend is present, fail visibly rather than claiming a scope opened.
    try:
        from matplotlib.backends import backend_registry
        available = {name.lower() for name in backend_registry.list_builtin()}
    except (ImportError, AttributeError):
        from matplotlib import rcsetup
        available = {name.lower() for name in getattr(rcsetup, "all_backends", ())}
    gui_backend = next((name for name in ("QtAgg", "TkAgg") if name.lower() in available), None)
    if gui_backend is None:
        raise RuntimeError("No supported Matplotlib GUI backend found (install PyQt6 or Tk).")
    matplotlib.use(gui_backend, force=True)
import matplotlib.pyplot as plt

BRIDGE, WIFI = "http://127.0.0.1:8088/telemetry", "http://192.168.4.1/telemetry"
RESIDUAL_THRESHOLD, CUSUM_K, CUSUM_H = 0.100, 0.02, 0.06
_demo_s_plus = _demo_s_minus = 0.0
_demo_rng_state = 0xA3E01234
_demo_frame_index = 0
_selftest_alarm_seen = False
_selftest_positive_seen = False
_selftest_negative_seen = False


def reset_demo_noise(seed=0xA3E01234):
    """Reset shared xorshift32 + Box-Muller noise used by dashboard/MATLAB demos."""
    global _demo_rng_state, _demo_frame_index
    _demo_rng_state = int(seed) & 0xFFFFFFFF
    _demo_frame_index = 0


def demo_normal():
    global _demo_rng_state
    x = _demo_rng_state
    x ^= (x << 13) & 0xFFFFFFFF
    x &= 0xFFFFFFFF
    x ^= x >> 17
    x &= 0xFFFFFFFF
    x ^= (x << 5) & 0xFFFFFFFF
    _demo_rng_state = x & 0xFFFFFFFF
    u1 = (_demo_rng_state + 0.5) / 4294967296.0
    x = _demo_rng_state
    x ^= (x << 13) & 0xFFFFFFFF
    x &= 0xFFFFFFFF
    x ^= x >> 17
    x &= 0xFFFFFFFF
    x ^= (x << 5) & 0xFFFFFFFF
    _demo_rng_state = x & 0xFFFFFFFF
    u2 = (_demo_rng_state + 0.5) / 4294967296.0
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2)


def http_get(url, timeout=0.3):
    try:
        d = json.loads(urllib.request.urlopen(url, timeout=timeout).read())
        required = ("x1", "x1_hat", "y_twin", "residual", "cusum_sp", "cusum_sm",
                    "u", "servo", "roll", "pitch", "alarm", "mode")
        if not isinstance(d, dict) or not all(k in d and d[k] is not None for k in required):
            return None
        try:
            if not all(math.isfinite(float(d[k])) for k in required):
                return None
        except (TypeError, ValueError):
            return None
        if url == BRIDGE:
            age = d.get("_age")
            if not isinstance(age, (int, float)) or not math.isfinite(age) or age < 0 or age > 1.0 or d.get("source") not in ("ESP32_FIRMWARE", "LIVE_HARDWARE", "FIRMWARE_MANUAL_OVERRIDE"):
                return None
        elif d.get("source") != "ESP32_FIRMWARE":
            return None
        return d
    except Exception:
        return None


ser = None
def open_serial():
    global ser
    try:
        import serial
        ser = serial.Serial(port=None, baudrate=460800, timeout=0.05)
        ser.port = args.port
        ser.dtr = False
        ser.rts = False
        ser.open()
        t0 = time.time()
        while time.time() - t0 < 0.8:
            if ser.in_waiting:
                return True
            time.sleep(0.02)
        ser.close(); ser = None
    except Exception:
        ser = None
    return False


def read_serial():
    try:
        line = ser.readline().decode("utf-8", "ignore").strip()
        if line.startswith("{") and line.endswith("}"):
            d = json.loads(line)
            required = ("x1", "x1_hat", "y_twin", "residual", "cusum_sp", "cusum_sm",
                        "u", "servo", "roll", "pitch", "alarm", "mode")
            if not isinstance(d, dict) or d.get("source") != "ESP32_FIRMWARE" or not all(k in d and d[k] is not None for k in required):
                return None
            if not all(math.isfinite(float(d[k])) for k in required):
                return None
            return d
    except Exception:
        pass
    return None


source = "bridge" if args.source == "auto" else args.source
label = ""
if args.selftest:
    source, label = "demo", "SELFTEST - deterministic injected-drift simulation"
elif source in ("auto", "bridge") and http_get(BRIDGE, .4):
    source, label = "bridge", "LIVE via dashboard bridge (127.0.0.1:8088)"
elif source in ("auto", "wifi") and http_get(WIFI, .5):
    source, label = "wifi", "LIVE ESP32 Wi-Fi (192.168.4.1)"
elif source == "usb" and open_serial():
    source, label = "usb", "LIVE USB serial (%s)" % args.port
elif source in ("bridge", "wifi", "usb"):
    # Keep the plot window open while a requested live stream reconnects.
    # Explicit live requests never silently fall back to synthetic data.
    source, label = source, "WAITING FOR LIVE %s TELEMETRY — no synthetic substitution" % source.upper()
if source == "demo" and not args.selftest:
    label = "SIMULATION ONLY - synthetic illustrative data (NOT hardware telemetry)"
print("[SCOPE]", label)

t0 = time.time()
def demo_sample(t):
    global _demo_s_plus, _demo_s_minus
    cyc = t % 8.0; r = 0.25 if cyc < 4 else 0.85; dt = cyc % 4
    phase = t % 48.0
    drift = 0.145 if 12 <= phase <= 18 else (-0.145 if 36 <= phase <= 42 else 0.0)
    # Model and reference share a synthetic nominal trajectory; only the simulated
    # measurement receives injected drift and sensor noise.
    nominal = r - 0.035 * math.exp(-5.2 * dt) * math.cos(14.2 * dt)
    # Independent synthetic noise for physical and twin channels: baseline
    # innovations must be zero-mean, not one-sided noise accumulating in CUSUM.
    x1 = nominal + drift + 0.003 * demo_normal()
    y_twin = nominal + 0.003 * demo_normal()
    x1_hat = x1 * .99 + .002 * demo_normal()
    signed_residual = x1 - y_twin
    res = abs(signed_residual)
    _demo_s_plus = max(0.0, _demo_s_plus + signed_residual - CUSUM_K)
    _demo_s_minus = max(0.0, _demo_s_minus - signed_residual - CUSUM_K)
    alarm = 2 if (res > RESIDUAL_THRESHOLD or max(_demo_s_plus, _demo_s_minus) >= CUSUM_H) else 0
    return dict(x1=x1, x1_hat=x1_hat, y_twin=y_twin, residual=res,
                cusum_sp=_demo_s_plus, cusum_sm=_demo_s_minus,
                u=min(1, max(0, .58 * r + .3 * (x1_hat - r))),
                servo=round(x1 * 180), roll=1.8 * math.sin(.9 * t), pitch=x1 * 15 - 7.5,
                dist2=50 + 25 * math.cos(.4 * t), alarm=alarm,
                reason="SYNTHETIC MODEL OFFSET" if alarm else "SIMULATION ONLY", mode=3,
                source="SIMULATION_ONLY")

keys = ["t", "x1", "x1_hat", "y_twin", "residual", "cusum_sp", "cusum_sm", "u", "servo", "roll", "pitch", "dist2"]
H = {k: collections.deque(maxlen=2000) for k in keys}

BG, PANEL, FG = "#080d12", "#0f171f", "#b8c7d0"
fig, axs = plt.subplots(2, 2, figsize=(13, 7.6), facecolor=BG)
fig.set_dpi(100)
fig.set_size_inches(13, 7.6, forward=True)
fig.canvas.manager.set_window_title("AeroLab Real-Time Scope (Python)") if hasattr(fig.canvas, "manager") and fig.canvas.manager else None
ax1, ax2, ax3, ax4 = axs.ravel()
for a in axs.ravel():
    a.set_facecolor(PANEL); a.tick_params(colors=FG); a.grid(True, alpha=.25)
    for s in a.spines.values(): s.set_color("#2a3a46")
ax4b = ax4.twinx()
ax4b.set_facecolor("none")
ax4b.tick_params(axis="y", colors="#60a5fa")
ax4b.spines["right"].set_color("#60a5fa")
def ln(ax, **k): return ax.plot([], [], **k)[0]
L = dict(
    x1=ln(ax1, c="#22c55e", lw=2, label="Firmware x1"), x1_hat=ln(ax1, c="#38bdf8", ls="--", label="Observer estimate"), y_twin=ln(ax1, c="#f59e0b", ls=":", lw=2, label="Twin output"),
    residual=ln(ax2, c="#ef4444", lw=2, label="Software-model residual |y−y_twin|"),
    u=ln(ax3, c="#a855f7", lw=2, label="LQR effort u"), servo=ln(ax3, c="#22d3ee", label="Servo / 180"),
    roll=ln(ax4, c="#34d399", label="Roll (deg)"), pitch=ln(ax4, c="#fb923c", label="Pitch (deg)"), dist2=ln(ax4b, c="#60a5fa", label="Servo US2 range (cm)"))
ax2b = ax2.twinx()
ax2b.set_facecolor("none")
ax2b.tick_params(axis="y", colors="#fbbf24")
ax2b.spines["right"].set_color("#fbbf24")
L["cusum_sp"] = ln(ax2b, c="#fbbf24", label="CUSUM S+")
L["cusum_sm"] = ln(ax2b, c="#38bdf8", ls="--", label="CUSUM S−")
ax2.axhline(RESIDUAL_THRESHOLD, c="#f87171", ls="--", label="Residual limit delta")
ax2b.axhline(CUSUM_H, c="#fbbf24", ls="--", label="CUSUM limit h")
for a, t_, yl in [(ax1, "Model states / observer (not plant validation)", (-.1, 1.25)), (ax2, "Residual r(t) and two-sided CUSUM", (0, .25)),
                  (ax3, "Actuator effort & servo", (-.05, 1.15)), (ax4, "IMU attitude and servo US2 range", (-60, 60))]:
    a.set_title(t_, color="#cfe6f5", fontweight="bold", fontsize=10); a.set_ylim(*yl)
    if a is not ax2:
        a.legend(loc="upper left", facecolor=PANEL, labelcolor=FG, fontsize=7, framealpha=.82)
ax1.set_ylabel("Normalized model state (unitless)", color=FG, fontsize=8)
ax2.set_ylabel("Absolute software-model residual |r|", color="#f87171", fontsize=8)
ax2.tick_params(axis="y", colors="#f87171")
ax2b.set_ylabel("CUSUM statistics S±", color="#fbbf24", fontsize=8)
_h1, _l1 = ax2.get_legend_handles_labels()
_h2, _l2 = ax2b.get_legend_handles_labels()
ax2.legend(_h1 + _h2, _l1 + _l2, loc="upper left", facecolor=PANEL, labelcolor=FG, fontsize=7, ncol=2, framealpha=.82)
ax2b.set_ylim(0, max(.10, CUSUM_H * 2.0))
ax4.set_ylabel("Attitude (deg)", color=FG, fontsize=8)
ax4b.set_ylabel("US2 range (cm)", color="#60a5fa", fontsize=8)
ax3.set_ylabel("Normalized effort / servo angle", color=FG, fontsize=8)
ax4b.set_ylim(0, 200)
_h4a, _l4a = ax4.get_legend_handles_labels()
_h4b, _l4b = ax4b.get_legend_handles_labels()
ax4.legend(_h4a + _h4b, _l4a + _l4b, loc="upper left", facecolor=PANEL, labelcolor=FG, fontsize=7, framealpha=.82)
ax3.set_xlabel("time (s)", color=FG); ax4.set_xlabel("time (s)", color=FG)
banner = fig.text(.5, .975, "", ha="center", va="top", fontsize=10, fontweight="bold", color="#33ff66",
                  bbox=dict(boxstyle="round", fc="#0b1620", ec="#2a7fa0"))
fig.tight_layout(rect=(0, 0, 1, .95))

import threading

latest_packet = None
latest_packet_time = None
packet_lock = threading.Lock()

def fetch_worker():
    global latest_packet, latest_packet_time
    while True:
        t = time.time() - t0
        d = None
        try:
            if source == "bridge":
                d = http_get(BRIDGE)
            elif source == "wifi":
                d = http_get(WIFI)
            elif source == "usb":
                d = read_serial()
        except Exception:
            pass

        if d:
            if source == "usb" and d.get("source") == "ESP32_FIRMWARE":
                try:
                    payload = json.dumps(d, separators=(",", ":")).encode("utf-8")
                    req = urllib.request.Request(
                        "http://127.0.0.1:8088/push", data=payload,
                        headers={"Content-Type": "application/json"}, method="POST")
                    urllib.request.urlopen(req, timeout=0.2).read()
                except Exception:
                    pass
            with packet_lock:
                latest_packet = d
                latest_packet_time = time.monotonic()
        time.sleep(0.04)

if not args.selftest and source != "demo":
    worker = threading.Thread(target=fetch_worker, daemon=True)
    worker.start()

def step(_=None):
    global _selftest_alarm_seen, _selftest_positive_seen, _selftest_negative_seen, _demo_frame_index
    if source == "demo":
        _demo_frame_index += 1
        t = _demo_frame_index * 0.05
        d = demo_sample(t)
    else:
        t = time.time() - t0
        with packet_lock:
            fresh = latest_packet_time is not None and time.monotonic() - latest_packet_time <= 1.0
            d = latest_packet if fresh else None
    if not args.selftest and source != "demo" and d is None:
        banner.set_color("#ff4444")
        banner.set_text("LIVE TELEMETRY STALE / DISCONNECTED — no synthetic substitution")
    if d:
        if args.selftest and int(d.get("alarm", 0) or 0) == 2:
            _selftest_alarm_seen = True
        if args.selftest:
            _selftest_positive_seen |= float(d.get("cusum_sp", 0) or 0) >= CUSUM_H
            _selftest_negative_seen |= float(d.get("cusum_sm", 0) or 0) >= CUSUM_H
        H["t"].append(t)
        for k in keys[1:]:
            raw = d.get(k)
            if k == "dist2":
                valid_demo = source == "demo" and isinstance(raw, (int, float)) and math.isfinite(raw)
                valid_live = (d.get("us2EchoOk") == 1 and isinstance(d.get("us2AgeMs"), (int, float))
                         and math.isfinite(d["us2AgeMs"]) and 0 <= d["us2AgeMs"] <= 300
                         and isinstance(raw, (int, float)) and math.isfinite(raw) and 2 <= raw <= 200)
                v = float(raw) if (valid_demo or valid_live) else float("nan")
            else:
                v = float(raw) if isinstance(raw, (int, float)) and math.isfinite(raw) else float("nan")
            H[k].append(v / 180.0 if k == "servo" else v)
        tt = np.fromiter(H["t"], float)
        for k, l in L.items(): l.set_data(tt, np.fromiter(H[k], float))
        visible = tt >= max(0, t - args.window)
        visible_residual = np.fromiter(H["residual"], float)[visible]
        visible_cusum = np.concatenate((np.fromiter(H["cusum_sp"], float)[visible],
                                        np.fromiter(H["cusum_sm"], float)[visible]))
        ax2.set_ylim(0, max(0.25, RESIDUAL_THRESHOLD * 1.25,
                            float(np.max(visible_residual)) * 1.1 if visible_residual.size else 0))
        ax2b.set_ylim(0, max(CUSUM_H * 1.5,
                             float(np.max(visible_cusum)) * 1.1 if visible_cusum.size else 0))
        for a in axs.ravel(): a.set_xlim(max(0, t - args.window), max(args.window, t))
        al = int(d.get("alarm", 0) or 0); col = ["#33ff66", "#ffb020", "#ff4444"][min(al, 2)]
        banner.set_color(col)
        range_status = "SIMULATION ONLY" if source == "demo" else "US2 NO FRESH ECHO"
        if source == "demo" and isinstance(d.get("dist2"), (int, float)):
            range_status = "SIM US2 %.1f cm" % d["dist2"]
        elif d.get("us2EchoOk") == 1 and isinstance(d.get("us2AgeMs"), (int, float)) and 0 <= d["us2AgeMs"] <= 300:
            raw_range = d.get("us2RawCm")
            if isinstance(raw_range, (int, float)) and 2 <= raw_range < 5:
                range_status = "US2 VERY CLOSE raw %.1f / filtered %.1f cm — VERIFY" % (raw_range, float(d.get("dist2", 0)))
            elif isinstance(raw_range, (int, float)):
                range_status = "US2 raw %.1f / filtered %.1f cm" % (raw_range, float(d.get("dist2", 0)))
            else:
                range_status = "US2 %.1f cm" % float(d.get("dist2", 0))
        banner.set_text("[%s] %s | %s | %s | res %.4f" % (["NOMINAL", "CAUTION", "RED ALARM"][min(al, 2)], d.get("source", label), d.get("reason", ""), range_status, float(d.get("residual", 0) or 0)))
    return list(L.values())

if args.selftest:
    reset_demo_noise(0xA3E01234)
    noise_vector = [demo_normal() for _ in range(6)]
    expected_noise = [-0.9434264076355248, 0.1615249851130549, 1.1813874691482749,
                      0.46748576490670124, 0.9034912155885615, 0.03947312977731734]
    if not np.allclose(noise_vector, expected_noise, rtol=0, atol=1e-12):
        raise SystemExit("selftest failed: shared demo noise vector differs")
    reset_demo_noise(0xA3E01234)
    _demo_s_plus = _demo_s_minus = 0.0
    first_expected = [
        {"x1": .22670395632875273, "y_twin": .23001881050699846, "x1_hat": .22679969170376174,
         "residual": .0033148541782457297, "u": .13803990751112852},
        {"x1": .24827653279053596, "y_twin": .24958454914258155, "x1_hat": .24587271372218522,
         "residual": .0013080163520455823, "u": .14376181411665556},
        {"x1": .25970138359194733, "y_twin": .2561467726704296, "x1_hat": .25557384424463697,
         "residual": .003554610921517709, "u": .1466721532733911},
    ]
    for i, expected in enumerate(first_expected, 1):
        actual = demo_sample(i * .05)
        bad = {k: (float(actual[k]), value) for k, value in expected.items()
               if abs(float(actual[k]) - value) > 1e-12}
        if bad:
            raise SystemExit("selftest failed: shared demo frame %d differs: %r" % (i, bad))
    reset_demo_noise(7)
    _demo_s_plus = _demo_s_minus = 0.0
    for i in range(900):
        step()
    if not (_selftest_alarm_seen and _selftest_positive_seen and _selftest_negative_seen):
        raise SystemExit("selftest failed: expected alarm and both positive/negative CUSUM detections")
    _demo_s_plus = _demo_s_minus = 0.0
    reset_demo_noise(13)
    _demo_s_plus = _demo_s_minus = 0.0
    baseline = [demo_sample(0.5 + i * 0.05) for i in range(200)]
    baseline_alarm = any(d["alarm"] for d in baseline)
    peak_sp = max(d["cusum_sp"] for d in baseline)
    peak_sm = max(d["cusum_sm"] for d in baseline)
    if baseline_alarm or peak_sp >= CUSUM_H or peak_sm >= CUSUM_H:
        raise SystemExit(f"selftest failed: healthy baseline false alarm (S+={peak_sp:.4f}, S-={peak_sm:.4f})")
    fig.savefig("scope_selftest.png", dpi=80, facecolor=BG); print("selftest OK -> scope_selftest.png"); sys.exit(0)

from matplotlib.animation import FuncAnimation
anim = FuncAnimation(fig, step, interval=50, blit=False, cache_frame_data=False)

try:
    from PyQt6 import QtCore
except Exception:
    QtCore = None

try:
    m = fig.canvas.manager
    if m and hasattr(m, "window"):
        w = m.window
        if hasattr(w, "showNormal"): w.showNormal()
        elif hasattr(w, "show"): w.show()
        if hasattr(w, "raise_"): w.raise_()
        if hasattr(w, "activateWindow"): w.activateWindow()
        if QtCore:
            QtCore.QTimer.singleShot(250, lambda: (w.raise_(), w.activateWindow()))
except Exception:
    pass

plt.show()

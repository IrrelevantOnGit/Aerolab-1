"""
AeroLab bridge  (v2)  -  http://127.0.0.1:8088
  /push (POST)   dashboard -> bridge, live telemetry (20 Hz)
  /telemetry     latest telemetry JSON  (read by MATLAB scope AND Python scope)
  /launch        start MATLAB scope  (auto-falls back to Python scope if MATLAB is missing)
  /python        start Python scope  (fast, no MATLAB needed)
  /status        what is installed / running
Fixes vs v1: finds ANY MATLAB version, never opens a 2nd MATLAB while one is still starting
(repeated clicks were what froze the laptop), starts MATLAB without the heavy desktop IDE,
and falls back to the Python scope automatically.
"""
import ctypes, glob, http.server, json, os, shutil, socketserver, subprocess, sys, threading, time, urllib.parse
from ctypes import wintypes

PORT = 8088
HERE = os.path.abspath(os.path.dirname(__file__))
latest_telemetry = {
    "x1": 0.5, "x1_hat": 0.49, "y_twin": 0.5, "residual": 0.005, "cusum_sp": 0.0,
    "u": 0.5, "servo": 90, "roll": 0.0, "pitch": 0.0, "dist1": 60.0, "dist2": 60.0,
    "vib": 0.02, "temp": 28.5, "hum": 50, "gas": 650, "ldr": 2200, "alarm": 0,
    "reason": "NO FRESH TELEMETRY", "mode": 1, "heap": 182000, "source": "UNVERIFIED_SOURCE",
}
procs = {"matlab": None, "python": None}
launch_messages = {"matlab": "Not started", "python": "Not started"}
launch_logs = {"matlab": None, "python": None}
last_push = 0.0
lock = threading.Lock()
usb_reader_status = {"port": "COM14", "connected": False, "packets": 0, "last_error": None}
usb_serial_handle = None
usb_write_lock = threading.Lock() if "threading" in globals() else None
python_launch_lock = threading.Lock()
matlab_launch_lock = threading.Lock()
window_focus_lock = threading.Lock()
MATLAB_STARTUP_COOLDOWN_S = 60.0


def find_matlab():
    """Return path of the newest matlab executable, or None."""
    env = os.environ.get("MATLAB_EXE")
    if env and os.path.exists(env):
        return env
    cands = []
    for root in (r"C:\Program Files\MATLAB", r"C:\Program Files (x86)\MATLAB",
                 os.path.expandvars(r"%LOCALAPPDATA%\Programs\MATLAB"), "/usr/local/MATLAB", "/Applications"):
        cands += glob.glob(os.path.join(root, "R20*", "bin", "matlab.exe"))
        cands += glob.glob(os.path.join(root, "R20*", "bin", "matlab"))
        cands += glob.glob(os.path.join(root, "MATLAB_R20*.app", "bin", "matlab"))
    if cands:
        return sorted(cands)[-1]          # R2025b > R2024a ...
    return shutil.which("matlab")


def alive(key):
    p = procs.get(key)
    return p is not None and p.poll() is None


def new_console():
    return subprocess.CREATE_NEW_CONSOLE if os.name == "nt" else 0


def find_scope_python():
    """Choose an installed Python that can import the actual plotting stack."""
    candidates = []
    if os.environ.get("AEROLAB_PYTHON_EXE"):
        candidates.append(os.environ["AEROLAB_PYTHON_EXE"])
    candidates.extend([sys.executable, shutil.which("python"), shutil.which("py")])
    if os.name == "nt":
        candidates.extend(glob.glob(os.path.join(os.environ.get("LOCALAPPDATA", ""),
                                                "Programs", "Python", "Python*", "python.exe")))
    seen = set()
    for candidate in candidates:
        if not candidate or candidate in seen or not os.path.isfile(candidate):
            continue
        seen.add(candidate)
        try:
            probe = subprocess.run([candidate, "-c", "import numpy, matplotlib"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=8, check=False)
            if probe.returncode == 0:
                return candidate
        except (OSError, subprocess.SubprocessError):
            continue
    return None


def scope_window(title_prefixes):
    """Find a visible top-level scope window (minimized windows still count)."""
    if os.name != "nt":
        return None
    user32 = ctypes.windll.user32
    user32.IsWindowVisible.argtypes = [wintypes.HWND]
    user32.IsWindowVisible.restype = wintypes.BOOL
    user32.GetWindowTextLengthW.argtypes = [wintypes.HWND]
    user32.GetWindowTextLengthW.restype = ctypes.c_int
    user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.GetWindowTextW.restype = ctypes.c_int
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    user32.EnumWindows.argtypes = [ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM), wintypes.LPARAM]
    user32.EnumWindows.restype = wintypes.BOOL
    found = []
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    def visit(hwnd, _):
        # Hidden windows must not be reported as "already open". Minimized
        # windows remain visible to Win32 and can be restored by the focus path.
        if not user32.IsWindowVisible(hwnd):
            return True
        length = user32.GetWindowTextLengthW(hwnd)
        if not length:
            return True
        title = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, title, length + 1)
        if any(title.value.casefold().startswith(prefix.casefold()) for prefix in title_prefixes):
            pid = wintypes.DWORD()
            user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
            if pid.value:
                found.append((pid.value, hwnd))
                return False
        return True

    callback = callback_type(visit)
    user32.EnumWindows(callback, 0)
    return found[0] if found else None


def focus_scope_window(title_prefixes):
    """Restore and foreground an existing scope so a button click is visible."""
    if os.name != "nt":
        return None
    with window_focus_lock:
        match = scope_window(title_prefixes)
        if not match:
            return None
        pid, hwnd = match
        user32 = ctypes.windll.user32
        user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
        user32.ShowWindow.restype = wintypes.BOOL
        user32.SetForegroundWindow.argtypes = [wintypes.HWND]
        user32.SetForegroundWindow.restype = wintypes.BOOL
        user32.BringWindowToTop.argtypes = [wintypes.HWND]
        user32.BringWindowToTop.restype = wintypes.BOOL
        user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
        user32.GetWindowThreadProcessId.restype = wintypes.DWORD
        user32.AttachThreadInput.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.BOOL]
        user32.AttachThreadInput.restype = wintypes.BOOL
        user32.GetForegroundWindow.restype = wintypes.HWND
        user32.FlashWindow.argtypes = [wintypes.HWND, wintypes.BOOL]
        user32.FlashWindow.restype = wintypes.BOOL
        kernel32 = ctypes.windll.kernel32
        kernel32.GetCurrentThreadId.restype = wintypes.DWORD
        user32.ShowWindow(hwnd, 9)  # SW_RESTORE also handles minimized windows.
        target_thread = user32.GetWindowThreadProcessId(hwnd, None)
        current_thread = kernel32.GetCurrentThreadId()
        foreground = user32.GetForegroundWindow()
        foreground_thread = user32.GetWindowThreadProcessId(foreground, None) if foreground else 0
        attached_threads = []
        for thread_id in {current_thread, foreground_thread}:
            if thread_id and thread_id != target_thread and user32.AttachThreadInput(thread_id, target_thread, True):
                attached_threads.append(thread_id)
        user32.BringWindowToTop(hwnd)
        user32.SetForegroundWindow(hwnd)
        for thread_id in attached_threads:
            user32.AttachThreadInput(thread_id, target_thread, False)
        foreground = user32.GetForegroundWindow()
        focused = int(foreground or 0) == int(hwnd)
        if not focused:
            user32.FlashWindow(hwnd, True)
        return pid, focused


def scope_window_message(engine, pid, focused, opened=False):
    if focused:
        state = "opened and focused" if opened else "restored and focused"
        return "%s scope window %s (PID %s)." % (engine, state, pid)
    return ("%s scope window is visible, but Windows kept focus elsewhere; "
            "it was restored and flashed. Use Alt+Tab if needed (PID %s)." % (engine, pid))


def python_scope_window_pid():
    """Find an already visible Python scope after a bridge restart."""
    match = scope_window((
        "AeroLab Real-Time Scope (Python)",
    ))
    return match[0] if match else None


def launch_python(mode):
    global launch_messages
    with python_launch_lock:
        existing_window = focus_scope_window(("AeroLab Real-Time Scope (Python)",))
        if existing_window:
            pid, focused = existing_window
            launch_messages["python"] = scope_window_message("Python", pid, focused)
            return {"status": "ok", "engine": "python", "message": launch_messages["python"],
                    "pid": pid, "focused": focused}
        if alive("python"):
            return {"status": "starting", "engine": "python", "message": "Python scope process is running; its window is not available yet. Check startup diagnostics before retrying.", "pid": procs["python"].pid, "log": launch_logs["python"]}
        return _start_python_scope(mode)


def _start_python_scope(mode):
    global launch_messages
    script = os.path.join(HERE, "python_realtime_scope.py")
    try:
        py_exe = find_scope_python()
        if not py_exe:
            return {"status": "error", "engine": "python",
                    "message": "No Python interpreter with numpy and matplotlib was found. Install requirements.txt or set AEROLAB_PYTHON_EXE."}
        log_path = os.path.join(HERE, "python_scope_startup.log")
        log_file = open(log_path, "a", encoding="utf-8", buffering=1)
        log_file.write("\n[%s] Starting Python scope\n" % time.strftime("%Y-%m-%d %H:%M:%S"))
        flags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0) if os.name == "nt" else 0
        # A deliberate dashboard DEMO selection gets a clearly labeled synthetic
        # scope; all transport modes stay live-only and never silently simulate.
        scope_source = "demo" if mode == "demo" else "bridge"
        procs["python"] = subprocess.Popen([py_exe, script, "--source", scope_source], cwd=HERE,
                                             stdin=subprocess.DEVNULL, stdout=log_file,
                                             stderr=subprocess.STDOUT, creationflags=flags)
        log_file.close()
        launch_logs["python"] = log_path
        deadline = time.monotonic() + 10.0
        while time.monotonic() < deadline:
            window = focus_scope_window(("AeroLab Real-Time Scope (Python)",))
            if window:
                pid, focused = window
                launch_messages["python"] = scope_window_message("Python", pid, focused, opened=True)
                return {"status": "ok", "engine": "python", "message": launch_messages["python"],
                        "pid": pid, "focused": focused, "log": log_path}
            if procs["python"].poll() is not None:
                launch_messages["python"] = "Python scope exited during startup. See " + log_path
                return {"status": "error", "engine": "python", "message": launch_messages["python"], "log": log_path}
            time.sleep(0.25)
        launch_messages["python"] = "Python process is running, but its scope window is not confirmed. See " + log_path
        return {"status": "starting", "engine": "python", "message": launch_messages["python"],
                "pid": procs["python"].pid, "log": log_path}
    except Exception as e:
        return {"status": "error", "engine": "python", "message": str(e)}


last_matlab_launch = 0.0


def is_matlab_running():
    try:
        out = subprocess.check_output(
            ["powershell", "-NoProfile", "-Command", "Get-Process -Name MATLAB -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id"],
            text=True, stderr=subprocess.DEVNULL, timeout=5
        ).strip()
        return bool(out)
    except Exception:
        return False


def matlab_scope_window_pid():
    """Return the PID hosting the actual scope figure, not MATLAB's launcher."""
    if os.name != "nt":
        return None
    # MATLAB varies window-title punctuation/prefixes across releases. Match
    # the distinctive scope fragment so status survives launcher handoff.
    match = scope_window(("AeroLab: Telemetry and Model-State Scope", "Telemetry and Model-State Scope"))
    return match[0] if match else None


def focus_matlab_scope_window():
    return focus_scope_window(("AeroLab: Telemetry and Model-State Scope",))


def kill_matlab():
    try:
        subprocess.run(["powershell", "-NoProfile", "-Command", "Stop-Process -Name *matlab* -Force -ErrorAction SilentlyContinue"], timeout=5)
        return {"status": "ok", "message": "All background MATLAB processes terminated."}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def launch_matlab(mode):
    global last_matlab_launch, launch_messages
    with matlab_launch_lock:
        existing_window = focus_matlab_scope_window()
        if existing_window:
            pid, focused = existing_window
            launch_messages["matlab"] = scope_window_message("MATLAB", pid, focused)
            return {"status": "ok", "engine": "matlab", "message": launch_messages["matlab"],
                    "pid": pid, "focused": focused}
        if alive("matlab"):
            return {"status": "starting", "engine": "matlab",
                    "message": "MATLAB launch is still running; the scope window is not visible yet.",
                    "pid": procs["matlab"].pid, "log": launch_logs["matlab"]}
        now = time.time()
        # Debounce only an in-flight launch; an existing window is handled above.
        if now - last_matlab_launch < MATLAB_STARTUP_COOLDOWN_S:
            return {"status": "starting", "engine": "matlab",
                    "message": "MATLAB was launched recently; preventing a duplicate while its scope window initializes.",
                    "log": launch_logs["matlab"]}
        exe = find_matlab()
        if not exe:
            res = launch_python(mode)
            res["message"] = "MATLAB not found -> opened Python Scope instead. " + res["message"]
            res["status"] = "fallback" if res["status"] in ("ok", "starting") else res["status"]
            return res
        try:
            last_matlab_launch = now
            with open(os.path.join(HERE, "matlab_target.txt"), "w") as f:
                f.write(mode)
            cmd = "cd('%s'); try, matlab_realtime_scope; catch ME, disp(getReport(ME,'extended')); fprintf(2,'\\nSCOPE STARTUP FAILED: %%s\\n',ME.message); end;" % HERE.replace("'", "''")
            log_path = os.path.join(HERE, "matlab_scope_startup.log")
            with open(log_path, "a", encoding="utf-8") as log_file:
                log_file.write("\n[%s] Starting MATLAB scope\n" % time.strftime("%Y-%m-%d %H:%M:%S"))
            # Keep MATLAB attached to the interactive desktop so graphics initialize visibly.
            proc = subprocess.Popen([exe, "-nosplash", "-logfile", log_path, "-r", cmd], cwd=HERE)
            procs["matlab"] = proc
            launch_logs["matlab"] = log_path
            # matlab.exe can hand off to MATLAB.exe and then exit successfully.
            # MATLAB may take longer than the former 12 s window to hand off
            # from matlab.exe to win64/MATLAB.exe and create the figure.
            deadline = time.monotonic() + 30.0
            while time.monotonic() < deadline:
                scope_window_match = focus_matlab_scope_window()
                if scope_window_match:
                    pid, focused = scope_window_match
                    launch_messages["matlab"] = scope_window_message("MATLAB", pid, focused, opened=True)
                    return {"status": "ok", "engine": "matlab", "message": launch_messages["matlab"],
                            "log": log_path, "pid": pid, "focused": focused}
                if proc.poll() is not None and proc.returncode not in (0, None) and not is_matlab_running():
                    break
                time.sleep(0.5)
            if proc.poll() is not None and proc.returncode not in (0, None) and not is_matlab_running():
                last_matlab_launch = 0.0
                launch_messages["matlab"] = "MATLAB failed during scope startup (code %s). See %s" % (proc.returncode, log_path)
                return {"status": "error", "engine": "matlab", "message": launch_messages["matlab"], "log": log_path}
            launch_messages["matlab"] = "MATLAB process is running; scope window is not confirmed yet. See " + log_path
            return {"status": "starting", "engine": "matlab", "message": launch_messages["matlab"],
                    "log": log_path, "pid": proc.pid}
        except Exception as e:
            last_matlab_launch = 0.0
            res = launch_python(mode)
            res["message"] = "MATLAB failed (%s) -> Python Scope fallback: " % e + res["message"]
            res["status"] = "fallback" if res["status"] in ("ok", "starting") else res["status"]
            return res


class Handler(http.server.BaseHTTPRequestHandler):
    def _json(self, obj, code=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        try:
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "*")
            self.end_headers()
        except Exception:
            pass

    def do_POST(self):
        global latest_telemetry, last_push
        try:
            path = self.path.split("?")[0]
            if path == "/cmd":
                n = int(self.headers.get("Content-Length", 0))
                if n <= 0 or n > 256:
                    return self._json({"status": "error", "message": "Invalid command payload."}, 400)
                payload = json.loads(self.rfile.read(n).decode("utf-8"))
                command = payload.get("command", "") if isinstance(payload, dict) else ""
                if (not isinstance(command, str) or not command or len(command) > 96
                        or any(ord(c) < 32 or ord(c) > 126 for c in command)):
                    return self._json({"status": "error", "message": "Command must be printable ASCII (1-96 characters)."}, 400)
                with usb_write_lock:
                    if usb_serial_handle is None or not usb_reader_status["connected"]:
                        return self._json({"status": "error", "message": "USB telemetry reader is not connected."}, 503)
                    usb_serial_handle.write((command + "\n").encode("ascii"))
                return self._json({"status": "ok", "message": "Command sent over USB."})
            elif path == "/push":
                n = int(self.headers.get("Content-Length", 0))
                if n > 0:
                    try:
                        d = json.loads(self.rfile.read(n).decode("utf-8"))
                        if isinstance(d, dict) and "x1" in d:
                            with lock:
                                latest_telemetry = d
                                last_push = time.time()
                    except Exception:
                        pass
                self._json({"status": "ok"})
            else:
                self._json({"status": "not found"}, 404)
        except Exception:
            pass

    def do_GET(self):
        try:
            u = urllib.parse.urlparse(self.path)
            qs = urllib.parse.parse_qs(u.query)
            mode = qs.get("mode", ["auto"])[0]
            if u.path == "/launch":
                self._json(launch_matlab(mode))
            elif u.path == "/kill_matlab":
                self._json(kill_matlab())
            elif u.path in ("/python", "/launch_python"):
                self._json(launch_python(mode))
            elif u.path == "/telemetry":
                with lock:
                    d = dict(latest_telemetry)
                age_s = round(time.time() - last_push, 2) if last_push else None
                d["_age"] = age_s
                d["age_s"] = age_s  # MATLAB-safe field name for freshness validation
                if age_s is None or age_s > 1.0:
                    d["source"] = "UNVERIFIED_SOURCE"
                self._json(d)
            elif u.path == "/status":
                scope_pid = matlab_scope_window_pid()
                python_pid = python_scope_window_pid()
                matlab_process_running = alive("matlab") or is_matlab_running()
                self._json({"status": "ready", "matlab_path": find_matlab(),
                            "matlab_running": matlab_process_running, "matlab_scope_visible": bool(scope_pid),
                            "matlab_scope_pid": scope_pid,
                            "python_running": alive("python") or bool(python_pid), "python_scope_pid": python_pid,
                            "python_scope_visible": bool(python_pid),
                            "matlab_launch": launch_messages["matlab"], "python_launch": launch_messages["python"],
                            "matlab_scope_log": launch_logs["matlab"] or os.path.join(HERE, "matlab_scope_startup.log"),
                            "python_scope_log": launch_logs["python"] or os.path.join(HERE, "python_scope_startup.log"),
                            "live_data_age_s": round(time.time() - last_push, 2) if last_push else None,
                            "usb": dict(usb_reader_status)})
            else:
                self._json({"status": "not found"}, 404)
        except Exception:
            pass

    def log_message(self, *a):
        pass


class Server(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    # Never let a second bridge bind the same dashboard port concurrently.
    allow_reuse_address = False


def acquire_bridge_singleton():
    """Keep one bridge instance per interactive Windows session."""
    if os.name != "nt":
        return True
    kernel32 = ctypes.windll.kernel32
    kernel32.CreateMutexW.argtypes = [wintypes.LPVOID, wintypes.BOOL, wintypes.LPCWSTR]
    kernel32.CreateMutexW.restype = wintypes.HANDLE
    kernel32.GetLastError.restype = wintypes.DWORD
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL
    handle = kernel32.CreateMutexW(None, True, "Local\\AeroLabTelemetryBridge-8088")
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    if kernel32.GetLastError() == 183:  # ERROR_ALREADY_EXISTS
        kernel32.CloseHandle(handle)
        return False
    global bridge_mutex_handle
    bridge_mutex_handle = handle  # Keep the handle alive for the server lifetime.
    return True


bridge_mutex_handle = None


def usb_telemetry_worker():
    """Read the firmware's 20 Hz JSON stream once and relay it to every scope."""
    global latest_telemetry, last_push, usb_serial_handle
    try:
        import serial
    except ImportError as exc:
        usb_reader_status["last_error"] = "pyserial unavailable: %s" % exc
        return
    port = usb_reader_status["port"]
    required = ("x1", "x1_hat", "y_twin", "residual", "cusum_sp", "cusum_sm",
                "u", "servo", "roll", "pitch", "dist1", "dist2", "alarm", "mode")
    while True:
        try:
            with serial.Serial(port=port, baudrate=460800, timeout=0.25,
                               write_timeout=0.25, dsrdtr=False, rtscts=False) as ser:
                # Leave DTR/RTS deasserted: do not reset the ESP32 on USB open.
                ser.dtr = False
                ser.rts = False
                usb_serial_handle = ser
                usb_reader_status.update(connected=True, last_error=None)
                while True:
                    raw = ser.readline()
                    if not raw.startswith(b"{"):
                        continue
                    try:
                        packet = json.loads(raw.decode("utf-8", "strict"))
                    except (UnicodeDecodeError, json.JSONDecodeError):
                        continue
                    if not isinstance(packet, dict) or packet.get("source") != "ESP32_FIRMWARE":
                        continue
                    if any(k not in packet or packet[k] is None for k in required):
                        continue
                    with lock:
                        latest_telemetry = packet
                        last_push = time.time()
                    usb_reader_status["packets"] += 1
                    if usb_reader_status["packets"] == 1:
                        print("[USB] Live ESP32 telemetry detected on %s @ 460800 baud." % port, flush=True)
        except Exception as exc:
            usb_serial_handle = None
            usb_reader_status.update(connected=False, last_error=str(exc))
            print("[USB] %s read failed: %s; retrying." % (port, exc), flush=True)
            time.sleep(2.0)


if __name__ == "__main__":
    try:
        if not acquire_bridge_singleton():
            print("[BRIDGE] Another AeroLab bridge already owns this session; not starting a duplicate.")
            sys.exit(0)
        with Server(("127.0.0.1", PORT), Handler) as httpd:
            print("[BRIDGE] http://127.0.0.1:%d  | MATLAB: %s" % (PORT, find_matlab() or "NOT FOUND (Python scope will be used)"))
            threading.Thread(target=usb_telemetry_worker, name="aerolab-usb-telemetry", daemon=True).start()
            httpd.serve_forever()
    except OSError:
        print("[BRIDGE] Port %d busy - bridge probably already running. That is fine." % PORT)
    except Exception as e:
        print("[BRIDGE] Error:", e)

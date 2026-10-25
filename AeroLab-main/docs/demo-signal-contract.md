# Shared demo-signal contract

The explicit DEMO in `dashboard.html`, `dashboard_analytics.html`, `python_realtime_scope.py`, and `matlab_realtime_scope.m` uses the same illustrative signal equations. DEMO is synthetic software data; it is never hardware evidence.

At sample indices `n = 1, 2, ...`, each demo advances on the nominal 50 ms grid `t = n·0.05 s`. Dashboard callbacks, Python animation callbacks, and MATLAB's simulation loop each increment one frame index per generated frame; callback wall-time jitter affects playback speed, not the synthetic timestamp or equations. Starting each explicit demo resets the same RNG seed and CUSUM state, so corresponding frame indices are intended to match across apps.

```text
c       = t mod 8
r       = 0.25 if c < 4, otherwise 0.85
τ       = c mod 4
nominal = r − 0.035 exp(−5.2τ) cos(14.2τ)
d       = +0.145 for 12 ≤ (t mod 48) ≤ 18
          −0.145 for 36 ≤ (t mod 48) ≤ 42
          0 otherwise
x1      = nominal + d + 0.003 z1
y_twin  = nominal + 0.003 z2
x1_hat  = 0.99 x1 + 0.002 z3
residual= |x1 − y_twin|
S+      = max(0, S+ + (x1 − y_twin) − 0.020)
S−      = max(0, S− − (x1 − y_twin) − 0.020)
u       = clamp(0.58r + 0.30(x1_hat − r), 0, 1)
servo   = round(180 x1) degrees
roll    = 1.8 sin(0.9t) degrees
pitch   = 15 x1 − 7.5 degrees
US2     = 50 + 25 cos(0.4t) cm (synthetic display channel only)
```

`z1..z3` are successive standard-normal values from the same xorshift32/Box–Muller generator, seeded with `0xA3E01234`. The RNG vector and first-frame golden values are asserted against production code in JavaScript, Python, and MATLAB (`test/dashboard_scope_test.js`, Python `--selftest`, and `test/matlab_demo_contract_test.m`). Frame-index timing is deliberate: traces are intended to agree sample-by-sample by frame index; OS callback scheduling can change playback wall-clock speed. These are code-level reproducibility checks, not physical plant equivalence.

The analytics phase-plane view additionally uses its synthetic `x2` auxiliary value; that field is not part of this four-scope cross-language comparison. Do not interpret any DEMO trace, residual, CUSUM, or servo response as a hardware measurement.

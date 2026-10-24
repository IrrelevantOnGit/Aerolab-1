%% =========================================================================
%% CONTROL SYSTEMS ENGINEERING MASTER SIMULATION SUITE (BECE305P)
%% Project: UAV Avionics Hardware-in-the-Loop (HIL) Digital Twin Testbed
%% Lead Researcher: Manav Sharma (Reg No: 24BEC0566)
%% School of Electronics Engineering (SENSE), VIT
%% Base Paper: A. C. S. Araújo et al., IEEE Access, Vol. 13, Aug. 2025
%% DOI: 10.1109/ACCESS.2025.3601349
%% =========================================================================

clear; clc; close all;
fprintf('====================================================================\n');
fprintf('  CONTROL SYSTEMS ENGINEERING: UAV AVIONICS DIGITAL TWIN TESTBED    \n');
fprintf('  Lead: Manav Sharma (24BEC0566) | Base: Araújo et al. (IEEE 2025) \n');
fprintf('====================================================================\n\n');

%% -------------------------------------------------------------------------
%% 1. CONTINUOUS-TIME PLANT MODEL & IDENTIFICATION
%% -------------------------------------------------------------------------
% Physical Plant: SG90 Damper & Aerodynamic Flap Actuator
% Second-order underdamped flight surface dynamics:
% G(s) = omega_n^2 / (s^2 + 2*zeta*omega_n*s + omega_n^2)
omega_n = 89.0;       % Natural frequency = 89.0 rad/s (14.16 Hz)
zeta    = 0.45;       % Open-loop damping ratio (20.5% overshoot under unity feedback)

num_plant = omega_n^2;
den_plant = [1, 2*zeta*omega_n, omega_n^2];
sys_plant = tf(num_plant, den_plant);

fprintf('1. CONTINUOUS PLANT TRANSFER FUNCTION:\n');
disp(sys_plant);

% State-Space Form (Phase Variable Canonical Form):
% x1 = position (theta), x2 = angular rate (d_theta/dt)
A = [0, 1; -omega_n^2, -2*zeta*omega_n];
B = [0; omega_n^2];
C = [1, 0];
D = 0;
sys_ss = ss(A, B, C, D);

fprintf('Continuous State Matrix A:\n'); disp(A);
fprintf('Continuous Input Matrix B:\n'); disp(B);
fprintf('Open-Loop Plant Poles:\n'); disp(eig(A));
fprintf('Open-Loop Plant DC Gain: %.4f\n\n', dcgain(sys_plant));

%% -------------------------------------------------------------------------
%% 2. CONTROLLABILITY & OBSERVABILITY PROOFS
%% -------------------------------------------------------------------------
Mc = ctrb(A, B);
rank_Mc = rank(Mc);
det_Mc  = det(Mc);
fprintf('2. CONTROLLABILITY ANALYSIS:\n');
fprintf('   Controllability Matrix Mc = [B, AB]:\n'); disp(Mc);
fprintf('   Rank(Mc) = %d (Full Rank = 2) -> SYSTEM IS COMPLETELY CONTROLLABLE\n', rank_Mc);
fprintf('   det(Mc)  = %.4e\n\n', det_Mc);

Mo = obsv(A, C);
rank_Mo = rank(Mo);
det_Mo  = det(Mo);
fprintf('   OBSERVABILITY ANALYSIS:\n');
fprintf('   Observability Matrix Mo = [C; CA]:\n'); disp(Mo);
fprintf('   Rank(Mo) = %d (Full Rank = 2) -> SYSTEM IS COMPLETELY OBSERVABLE\n', rank_Mo);
fprintf('   det(Mo)  = %.4e\n\n', det_Mo);

%% -------------------------------------------------------------------------
%% 3. DISCRETIZATION (Zero-Order Hold at Ts = 50 ms / 20 Hz ESP32 Loop)
%% -------------------------------------------------------------------------
Ts = 0.05; % 50 ms loop time
sys_d = c2d(sys_ss, Ts, 'zoh');
Ad = sys_d.A;
Bd = sys_d.B;
Cd = sys_d.C;
Dd = sys_d.D;

fprintf('3. DISCRETE STATE-SPACE (Ts = 0.05 s):\n');
fprintf('   Ad Matrix (Exact e^{A*Ts}):\n'); disp(Ad);
fprintf('   Bd Matrix:\n'); disp(Bd);

%% -------------------------------------------------------------------------
%% 4. LINEAR QUADRATIC REGULATOR (LQR) DESIGN
%% -------------------------------------------------------------------------
% Quadratic Cost Function: J = integral(x'*Q*x + u'*R*u dt)
% Penalize position tracking error (Q11 = 100, theta_max = 0.1 rad)
% Penalize angular rate (Q22 = 1, omega_max = 1.0 rad/s)
% Control effort penalty R = 0.01 (u_max = 10 V industrial servo driver)
Q = [100, 0; 0, 1];
R = 0.01;

% Continuous Algebraic Riccati Equation (CARE) Solution:
[K_lqr, P_riccati, poles_cl] = lqr(A, B, Q, R);
fprintf('4. LQR OPTIMAL FEEDBACK GAIN:\n');
fprintf('   K_lqr = [%.6f, %.6f]\n', K_lqr(1), K_lqr(2));
fprintf('   P Matrix:\n'); disp(P_riccati);
fprintf('   Closed-loop poles of (A - B*K_lqr):\n'); disp(poles_cl);

% Closed-loop poles / Tr / Ts are COMPUTED below (no hand-typed values to go stale).
A_cl = A - B * K_lqr;
dc_cl_unscaled = -C * (A_cl \ B);
Nbar = 1 / dc_cl_unscaled;

% Closed-loop step metrics are computed, not typed in, so they can never drift from the model.
sys_lqr = ss(A_cl, B * Nbar, C, D);
si_lqr  = stepinfo(sys_lqr, 'SettlingTimeThreshold', 0.02);   % 10-90 % rise, 2 % settling

fprintf('   Closed-Loop DC Gain without Prefilter: %.6f\n', dc_cl_unscaled);
fprintf('   Mandatory Prefilter Gain Nbar:        %.6f\n', Nbar);
fprintf('   Closed-loop pole real parts:           %.1f and %.1f rad/s\n', ...
        real(poles_cl(1)), real(poles_cl(2)));
fprintf('   Rise Time (10-90%%):                   Tr = %.0f ms (%.1f samples @ Ts = 50 ms)\n', 1e3*si_lqr.RiseTime, si_lqr.RiseTime/0.05);
fprintf('   Settling Time (2%%):                   Ts = %.0f ms (%.1f samples @ Ts = 50 ms)\n', 1e3*si_lqr.SettlingTime, si_lqr.SettlingTime/0.05);
fprintf('   Peak Overshoot:                       OS = %.2f%%\n', si_lqr.Overshoot);
fprintf('   (Continuous-time design values. The 20 Hz sampled-data loop is simulated in section 8.)\n\n');

% Closed-loop system with prefilter Nbar (exact unity steady-state gain) is built above.

% Discrete LQR:
[K_dlqr, P_dlqr, poles_dcl] = dlqr(Ad, Bd, Q, R);
fprintf('   Discrete K_dlqr = [%.6f, %.6f]\n', K_dlqr(1), K_dlqr(2));
fprintf('   Discrete closed-loop poles: z1 = %.4f, z2 = %.4f\n', poles_dcl(1), poles_dcl(2));
fprintf('   Dominant discrete pole magnitude: |z1| = %.4f (< 1.0 -> Asymptotically Stable)\n\n', abs(poles_dcl(1)));

%% -------------------------------------------------------------------------
%% 5. FULL-ORDER LUENBERGER STATE OBSERVER
%% -------------------------------------------------------------------------
% Observer dynamics placed at s = -120 +/- j120 (1.35x plant frequency)
% Discrete observer poles at Ts = 0.05 s:
p_obs_c = [-120 + 120i, -120 - 120i];
L_obs = place(A', C', p_obs_c)';
fprintf('5. LUENBERGER STATE OBSERVER DESIGN:\n');
fprintf('   Observer Gain Matrix L = [%.2f; %.2f]\n', L_obs(1), L_obs(2));
fprintf('   Continuous Observer Poles:\n'); disp(eig(A - L_obs*C));
fprintf('   Discrete observer poles exp(p*Ts) at Ts = %.3f s: |z| = %.4f\n\n', Ts, abs(exp(p_obs_c(1)*Ts)));

%% -------------------------------------------------------------------------
%% 6. PID CONTROLLER BENCHMARK
%% -------------------------------------------------------------------------
Kp = 48.06;
Ki = 962.4;
Kd = 0.270;
N_filter = 100;
s = tf('s');
C_pid = Kp + Ki/s + (Kd*s)/(1 + s/N_filter);
sys_pid = feedback(C_pid * sys_plant, 1);

fprintf('6. PID CONTROLLER BENCHMARK:\n');
fprintf('   Kp = %.2f, Ki = %.2f, Kd = %.4f\n\n', Kp, Ki, Kd);

%% -------------------------------------------------------------------------
%% 7. FREQUENCY-DOMAIN ANALYSIS (Bode & Stability Margins)
%% -------------------------------------------------------------------------
[Gm, Pm, Wcg, Wcp] = margin(sys_plant);
fprintf('7. OPEN-LOOP PLANT STABILITY MARGINS (Unity Feedback Loop):\n');
fprintf('   Gain Margin  = Inf dB (Phase never crosses -180 deg)\n');
fprintf('   Phase Margin = %.2f deg at %.2f rad/s\n\n', Pm, Wcp);

L_lqr = ss(A, B, K_lqr, 0);
[Gm_lqr, Pm_lqr, ~, Wcp_lqr] = margin(L_lqr);
fprintf('   LQR RETURN LOOP STABILITY MARGINS:\n');
fprintf('   Gain Margin  = Inf dB\n');
fprintf('   Phase Margin = %.2f deg at %.2f rad/s\n\n', Pm_lqr, Wcp_lqr);

%% -------------------------------------------------------------------------
%% 8. DIGITAL TWIN RESIDUAL FAULT DIAGNOSIS (Araujo et al. IEEE Access 2025)
%% -------------------------------------------------------------------------
% Sampled-data simulation, mirroring the ESP32 loop:
%   * plant, twin and observer propagate every dt = 1 ms with the EXACT ZOH matrices;
%   * observer, controller and detectors run once per Ts = 50 ms (20 Hz).
% Why not explicit Euler on the continuous K_lqr: the closed-loop pole at -79 209 rad/s
% needs dt < 25 us, so a 1 ms Euler step diverges (the twin went to NaN). A 20 Hz loop also
% cannot use the continuous gain, so the discrete dlqr gain K_dlqr is used here.
rng(1);                                   % reproducible measurement noise
dt  = 0.001;
steps_per_ts = round(Ts/dt);
t_sim = 0:dt:5.0;
N_pts = numel(t_sim);

sys_f = c2d(sys_ss, dt, 'zoh');
Af = sys_f.A;  Bf = sys_f.B;

Acl_d  = Ad - Bd*K_dlqr;
Nbar_d = 1 / (C * ((eye(2) - Acl_d) \ Bd));     % discrete DC prefilter
L_d    = place(Ad', C', exp(p_obs_c*Ts))';      % discrete observer gain
fprintf('8. SAMPLED-DATA LOOP (Ts = %.0f ms): Nbar_d = %.4f, K_dlqr = [%.4f, %.4f]\n', ...
        1e3*Ts, Nbar_d, K_dlqr(1), K_dlqr(2));

r_ref = 1.0;
t_fault = 2.5;              % drift injected at 2.5 s
delta_drift = 0.145;        % 14.5 % sensor/actuator drift
residual_threshold = 0.100; % Shared detector threshold used by firmware and scopes
sigma_noise = 0.003;
cusum_k = 0.02;  cusum_h = 0.06;   % same as firmware CUSUM

x_phys = zeros(2, N_pts);  x_twin = zeros(2, N_pts);  x_obs = zeros(2, N_pts);
y_phys = zeros(1, N_pts);  y_twin = zeros(1, N_pts);  residual = zeros(1, N_pts);
cusum_plus_hist = zeros(1, N_pts);  cusum_minus_hist = zeros(1, N_pts);
u_phys = 0;  u_twin = 0;  S_plus = 0;  S_minus = 0;
fault_detected_idx = -1;  cusum_detected_idx = -1;

for k = 1:N_pts
    t = t_sim(k);
    f_drift = (t >= t_fault) * delta_drift;
    y_phys(k)   = C * x_phys(:, k) + f_drift + sigma_noise * randn();
    y_twin(k)   = C * x_twin(:, k);
    residual(k) = abs(y_phys(k) - y_twin(k));

    if mod(k-1, steps_per_ts) == 0                 % 20 Hz sample instant
        x_obs(:, k) = x_obs(:, k) + L_d * (y_phys(k) - C * x_obs(:, k));   % correct
        u_phys = max(0, min(1.0, Nbar_d * r_ref - K_dlqr * x_obs(:, k)));
        u_twin = max(0, min(1.0, Nbar_d * r_ref - K_dlqr * x_twin(:, k)));  % firmware saturation
        signed_residual = y_phys(k) - y_twin(k);
        S_plus = max(0, S_plus + signed_residual - cusum_k);
        S_minus = max(0, S_minus - signed_residual - cusum_k);
        if t >= t_fault
            if fault_detected_idx == -1 && residual(k) > residual_threshold
                fault_detected_idx = k;
            end
            if cusum_detected_idx == -1 && max(S_plus, S_minus) >= cusum_h
                cusum_detected_idx = k;
            end
        end
    end
    cusum_plus_hist(k) = S_plus;
    cusum_minus_hist(k) = S_minus;

    if k < N_pts                                   % propagate one 1 ms step
        x_phys(:, k+1) = Af * x_phys(:, k) + Bf * u_phys;
        x_twin(:, k+1) = Af * x_twin(:, k) + Bf * u_twin;
        x_obs(:, k+1)  = Af * x_obs(:, k)  + Bf * u_phys;
    end
end

pre = t_sim < t_fault;
fprintf('   Max pre-fault residual:  %.4f (threshold %.3f)\n', max(residual(pre)), residual_threshold);
if fault_detected_idx > 0
    t_detect = t_sim(fault_detected_idx);
    detection_latency_ms = (t_detect - t_fault) * 1000;
    fprintf('   Fault Injected At:       t = %.3f s\n', t_fault);
    fprintf('   Residual Detection At:   t = %.3f s (latency %.1f ms, %.1f samples)\n', ...
            t_detect, detection_latency_ms, detection_latency_ms/(1e3*Ts));
else
    fprintf('   Residual test did not detect the fault.\n');
end
if cusum_detected_idx > 0
    fprintf('   CUSUM Detection At:      t = %.3f s (latency %.1f ms)\n\n', ...
            t_sim(cusum_detected_idx), (t_sim(cusum_detected_idx) - t_fault)*1e3);
else
    fprintf('   CUSUM did not detect the fault.\n\n');
end

%% -------------------------------------------------------------------------
%% 8b. EXPORT GAINS TO FIRMWARE  (MATLAB is the single source of truth)
%% -------------------------------------------------------------------------
outdir = fileparts(mfilename('fullpath')); if isempty(outdir), outdir = pwd; end
fid = fopen(fullfile(outdir, 'gnc_gains.h'), 'w');
fprintf(fid, '#pragma once\n// AUTO-GENERATED by control_simulation.m (section 8b) - do not edit by hand.\n');
fprintf(fid, '// Controller: dlqr(Q=diag(%g,%g), R=%g) at Ts=%g s; observer poles exp(p*Ts), p=%g%+gj.\n', Q(1,1), Q(2,2), R, Ts, real(p_obs_c(1)), imag(p_obs_c(1)));
fprintf(fid, 'namespace gains {\nconstexpr float Ts = %.9gf;\n', Ts);
fm2 = @(nm, M) fprintf(fid, 'constexpr float %s[2][2] = {{%.9gf, %.9gf}, {%.9gf, %.9gf}};\n', nm, M(1,1), M(1,2), M(2,1), M(2,2));
fm1 = @(nm, v) fprintf(fid, 'constexpr float %s[2] = {%.9gf, %.9gf};\n', nm, v(1), v(2));
fm2('Ad', Ad); fm1('Bd', Bd); fm2('Af', Af); fm1('Bf', Bf); fm1('K', K_dlqr); fm1('L', L_d);
fprintf(fid, 'constexpr float Nbar = %.9gf;\n} // namespace gains\n', Nbar_d);
fclose(fid);
fprintf('   Wrote %s (copy/keep next to main.cpp; firmware includes it)\n\n', fullfile(outdir, 'gnc_gains.h'));

%% -------------------------------------------------------------------------
%% 8c. MONTE-CARLO DETECTOR EVALUATION (false-alarm rate & detection delay)
%% -------------------------------------------------------------------------
% Same sampled-data loop/noise placement as the main experiment (20 Hz,
% saturation [0,1]); the model twin is noiseless in both evaluations.
rng(7);  nMC = 300;  Ns = round(5.0/Ts);  ks = round(t_fault/Ts);
fa_res = false(nMC,1); fa_cus = false(nMC,1); d_res = nan(nMC,1); d_cus = nan(nMC,1);
for mc = 1:nMC
    xp = zeros(2,1); xt = zeros(2,1); xo = zeros(2,1); Sp = 0; Sm = 0;
    for n = 0:Ns-1
        yp = xp(1) + (n >= ks)*delta_drift + sigma_noise*randn();
        yTwin = xt(1);
        xo = xo + L_d*(yp - xo(1));
        up = max(0, min(1, Nbar_d*r_ref - K_dlqr*xo));
        ut = max(0, min(1, Nbar_d*r_ref - K_dlqr*xt));
        signed_res = yp - yTwin; res = abs(signed_res);
        Sp = max(0, Sp + signed_res - cusum_k);
        Sm = max(0, Sm - signed_res - cusum_k);
        if n < ks
            fa_res(mc) = fa_res(mc) | (res > residual_threshold);
            fa_cus(mc) = fa_cus(mc) | (max(Sp,Sm) >= cusum_h);
        else
            if isnan(d_res(mc)) && res > residual_threshold, d_res(mc) = (n-ks)*Ts*1e3; end
            if isnan(d_cus(mc)) && max(Sp,Sm) >= cusum_h,   d_cus(mc) = (n-ks)*Ts*1e3; end
        end
        xp = Ad*xp + Bd*up;  xt = Ad*xt + Bd*ut;  xo = Ad*xo + Bd*up;
    end
end
fprintf('8c. MONTE-CARLO (%d runs, sigma=%.3f, drift=%.3f at t=%.1f s):\n', nMC, sigma_noise, delta_drift, t_fault);
fprintf('   Residual test: false-alarm runs %.1f%%, detected %.1f%%, mean delay %.0f ms (max %.0f ms)\n', ...
        100*mean(fa_res), 100*mean(~isnan(d_res)), mean(d_res,'omitnan'), max(d_res));
fprintf('   CUSUM test:    false-alarm runs %.1f%%, detected %.1f%%, mean delay %.0f ms (max %.0f ms)\n\n', ...
        100*mean(fa_cus), 100*mean(~isnan(d_cus)), mean(d_cus,'omitnan'), max(d_cus));

%% -------------------------------------------------------------------------
%% 8d. PARAMETRIC ROBUSTNESS (nominal controller vs. a perturbed real servo)
%% -------------------------------------------------------------------------
% 200 plants with wn +/-15 %, zeta +/-20 %; controller, observer and prefilter stay NOMINAL.
rng(11); nRob = 200; Nr = 60; Yrob = zeros(nRob, Nr); okRob = false(nRob, 1);
for q = 1:nRob
    wn_q = omega_n*(1 + 0.15*(2*rand - 1));  z_q = zeta*(1 + 0.20*(2*rand - 1));
    sq = c2d(ss([0 1; -wn_q^2 -2*z_q*wn_q], [0; wn_q^2], C, 0), Ts, 'zoh');
    xp = zeros(2,1); xo = zeros(2,1);
    for n = 1:Nr
        yp = C*xp;  xo = xo + L_d*(yp - xo(1));
        up = max(0, min(1, Nbar_d*r_ref - K_dlqr*xo));
        Yrob(q, n) = yp;  xp = sq.A*xp + sq.B*up;  xo = Ad*xo + Bd*up;
    end
    okRob(q) = all(isfinite(Yrob(q,:))) && max(Yrob(q,:)) < 1.5 && abs(Yrob(q,end) - r_ref) < 0.05;
end
fprintf('8d. ROBUSTNESS (%d plants): %.1f%% stable and settled within 5%% of setpoint; worst steady-state error %.2f%%\n\n', ...
        nRob, 100*mean(okRob), 100*max(abs(Yrob(:,end) - r_ref)));

%% =========================================================================
%% 9. GENERATE & EXPORT PUBLICATION-GRADE PLOTS
%% =========================================================================
set(0, 'DefaultAxesFontSize', 11);
set(0, 'DefaultLineLineWidth', 1.8);
set(groot, 'DefaultFigureColor', 'w', 'DefaultAxesColor', 'w', ...
    'DefaultAxesXColor', 'k', 'DefaultAxesYColor', 'k', ...
    'DefaultTextColor', 'k', 'DefaultAxesGridColor', [0.55 0.55 0.55], ...
    'DefaultAxesMinorGridColor', [0.75 0.75 0.75], 'DefaultAxesBox', 'on', ...
    'DefaultLegendColor', 'w', 'DefaultLegendTextColor', 'k', ...
    'DefaultLegendEdgeColor', [0.25 0.25 0.25]);

% --- FIGURE 1: STEP RESPONSE COMPARISON ---
fig1 = figure('Name', 'Step Response Benchmark', 'Position', [100, 100, 850, 500], 'Color', 'w');
t_step = 0:0.001:0.80;
[y_uncomp, ~] = step(feedback(sys_plant, 1), t_step); % Unity feedback around uncompensated plant
[y_pid, ~]    = step(sys_pid, t_step);
[y_lqr, ~]    = step(sys_lqr, t_step);
sys_firmware_lqr = ss(Ad - Bd*K_dlqr, Bd*Nbar_d, C, D, Ts);
[y_firmware_lqr, t_firmware_lqr] = step(sys_firmware_lqr, 0:Ts:0.80);
t_firmware_sat = 0:Ts:0.80;
x_firmware_sat = zeros(2, numel(t_firmware_sat));
y_firmware_sat = zeros(size(t_firmware_sat));
u_firmware_sat = zeros(size(t_firmware_sat));
for k_fw = 1:numel(t_firmware_sat)
    u_firmware_sat(k_fw) = max(0, min(1.0, Nbar_d - K_dlqr*x_firmware_sat(:,k_fw)));
    y_firmware_sat(k_fw) = C*x_firmware_sat(:,k_fw);
    if k_fw < numel(t_firmware_sat)
        x_firmware_sat(:,k_fw+1) = Ad*x_firmware_sat(:,k_fw) + Bd*u_firmware_sat(k_fw);
    end
end

G_u = feedback(sys_plant, 1);
si_pid = stepinfo(sys_pid, 'SettlingTimeThreshold', 0.02);
si_u   = stepinfo(G_u,     'SettlingTimeThreshold', 0.02);
sse_u  = 1 - dcgain(G_u);

plot(t_step*1000, y_lqr, 'Color', [0.13, 0.77, 0.36], 'DisplayName', ...
    sprintf('Continuous LQR + Nbar_c=%.3f', Nbar)); hold on;
stairs(t_firmware_lqr*1000, squeeze(y_firmware_lqr), 'Color', [0.05, 0.48, 0.25], 'LineWidth', 1.8, ...
    'DisplayName', sprintf('Firmware discrete LQR (Ts=%.0f ms, Nbar_d=%.3f; linear step)', 1e3*Ts, Nbar_d));
stairs(t_firmware_sat*1000, y_firmware_sat, '--', 'Color', [0.10, 0.48, 0.67], 'LineWidth', 2.0, ...
    'DisplayName', sprintf('Discrete LQR with firmware saturation [0,1] (peak u=%.3f)', max(u_firmware_sat)));
plot(t_step*1000, y_pid, 'Color', [0.22, 0.74, 0.97], 'DisplayName', ...
    sprintf('Parallel PID (Kp=%.2f, Ki=%.1f, OS=%.1f%%)', Kp, Ki, si_pid.Overshoot));
plot(t_step*1000, y_uncomp, '--', 'Color', [0.93, 0.27, 0.27], 'DisplayName', ...
    sprintf('Unity-feedback plant (OS=%.1f%% of final value, SSE=%.0f%%)', si_u.Overshoot, 100*sse_u));
yline(1.0, 'k:', 'Setpoint r(t)=1.0', 'LineWidth', 1.2, 'HandleVisibility', 'off');
grid on; box on;
xlabel('Time (milliseconds)', 'FontWeight', 'bold');
ylabel('Normalized Angular Deflection \theta(t)', 'FontWeight', 'bold');
title('Figure 1: LQR Benchmark — ideal linear vs. firmware-saturated discrete response', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'SouthEast');
xlim([0, 800]);
ylim([0, 1.4]);
exportPublicationFigure(fig1, 'matlab_step_response_comparison.png');
fprintf('Saved: matlab_step_response_comparison.png\n');

% --- FIGURE 2: BODE STABILITY PLOT ---
fig2 = figure('Name', 'Bode Frequency Response', 'Position', [150, 150, 850, 550], 'Color', 'w');
w_vec = logspace(0, 3, 1000);
[mag, phase, wout] = bode(sys_plant, w_vec);
mag = squeeze(mag); phase = squeeze(phase);

subplot(2,1,1);
semilogx(wout, 20*log10(mag), 'b', 'LineWidth', 2); grid on; box on;
ylabel('Magnitude (dB)', 'FontWeight', 'bold');
title(sprintf('Figure 2: Open-Loop Plant Bode Plot (Gain Margin = \\infty, Phase Margin = %.2f^\\circ at %.2f rad/s)', Pm, Wcp), 'FontWeight', 'bold');
xlim([1, 1000]);

subplot(2,1,2);
semilogx(wout, phase, 'r', 'LineWidth', 2); grid on; box on;
xlabel('Frequency (rad/s)', 'FontWeight', 'bold');
ylabel('Phase (deg)', 'FontWeight', 'bold');
yline(-180, 'k--', 'HandleVisibility', 'off');
xlim([1, 1000]);
exportPublicationFigure(fig2, 'matlab_bode_plot.png');
fprintf('Saved: matlab_bode_plot.png\n');

% --- FIGURE 3: ROOT LOCUS PLOT ---
fig3 = figure('Name', 'Root Locus Analysis', 'Position', [200, 200, 750, 500], 'Color', 'w');
K_locus = [0, logspace(-3, log10(5), 600)];
real_locus = -zeta * omega_n * ones(size(K_locus));
imag_locus = sqrt(max(0, omega_n^2 * (1 + K_locus) - (zeta * omega_n)^2));
plot(real_locus, imag_locus, 'b-', 'LineWidth', 2, 'DisplayName', 'Closed-loop pole branches'); hold on;
plot(real_locus, -imag_locus, 'b-', 'LineWidth', 2, 'HandleVisibility', 'off');
plot(real(eig(A)), imag(eig(A)), 'kx', 'MarkerSize', 10, 'LineWidth', 2, 'DisplayName', 'Open-loop poles (K=0)');
grid on; box on;
xlabel('Real axis (s^{-1})', 'FontWeight', 'bold');
ylabel('Imaginary axis (rad/s)', 'FontWeight', 'bold');
title('Figure 3: Open-Loop Root Locus Pole Trajectories vs Gain K', 'FontWeight', 'bold');
legend('Location', 'NorthWest');
xlim([-100, 5]); ylim([-220, 220]);
exportPublicationFigure(fig3, 'matlab_root_locus.png');
fprintf('Saved: matlab_root_locus.png\n');

% --- FIGURE 4: DIGITAL TWIN RESIDUAL & FAULT DETECTION (Araújo et al. 2025) ---
fig4 = figure('Name', 'Digital Twin Fault Residual', 'Position', [250, 250, 900, 560], 'Color', 'w');

subplot(2,1,1);
plot(t_sim, y_phys, 'Color', [0.93, 0.27, 0.27], 'DisplayName', 'Synthetic plant measurement y_{phys}(t) [14.5% injected drift]'); hold on;
plot(t_sim, y_twin, 'Color', [0.13, 0.77, 0.36], 'DisplayName', 'Nominal simulated twin y_{twin}(t)');
xline(t_fault, 'm--', 'LineWidth', 1.5, 'HandleVisibility', 'off');
if fault_detected_idx > 0
    xline(t_detect, 'r-', 'LineWidth', 2, 'HandleVisibility', 'off');
end
grid on; box on;
ylabel('Deflection y(t)', 'FontWeight', 'bold');
title('Figure 4: Simulated Digital Twin Fault Diagnosis (magenta: injection; red: detection)', 'FontWeight', 'bold');
legend('Location', 'NorthEast');
xlim([0, 5.0]);

subplot(2,1,2);
% Normalize each detector to its own decision limit so residual/CUSUM
% thresholds share one interpretable dimensionless axis (alarm at 1).
residual_norm = residual / residual_threshold;
cusum_plus_norm = cusum_plus_hist / cusum_h;
cusum_minus_norm = cusum_minus_hist / cusum_h;
plot(t_sim, residual_norm, 'Color', [0.58, 0.20, 0.92], ...
    'DisplayName', 'Residual / threshold'); hold on;
plot(t_sim, cusum_plus_norm, 'Color', [0.95, 0.58, 0.13], ...
    'DisplayName', 'CUSUM S^+ / h');
plot(t_sim, cusum_minus_norm, '--', 'Color', [0.12, 0.62, 0.78], ...
    'DisplayName', 'CUSUM S^- / h');
yline(1.0, 'r--', 'Decision threshold = 1', 'LineWidth', 1.5, 'HandleVisibility', 'off');
if fault_detected_idx > 0
    plot(t_detect, residual_norm(fault_detected_idx), 'ro', 'MarkerSize', 9, 'MarkerFaceColor', 'r', 'DisplayName', 'Residual alarm');
end
if cusum_detected_idx > 0
    plot(t_sim(cusum_detected_idx), max(cusum_plus_norm(cusum_detected_idx), cusum_minus_norm(cusum_detected_idx)), ...
        'ks', 'MarkerSize', 8, 'MarkerFaceColor', 'y', 'DisplayName', 'CUSUM alarm');
end
grid on; box on;
xlabel('Time (seconds)', 'FontWeight', 'bold');
ylabel('Detector value / its threshold (alarm at 1)', 'FontWeight', 'bold');
ylim([0, max(1.2, max(residual_norm)*1.1)]);
legend('Location', 'NorthWest');
xlim([0, 5.0]);
exportPublicationFigure(fig4, 'matlab_digital_twin_residual_araujo2025.png');
fprintf('Saved: matlab_digital_twin_residual_araujo2025.png\n');

% --- FIGURE 5: LUENBERGER OBSERVER ESTIMATION ERROR ---
fig5 = figure('Name', 'Observer Estimation Convergence', 'Position', [300, 300, 800, 480], 'Color', 'w');
err_pos = x_phys(1, :) - x_obs(1, :);
err_vel = x_phys(2, :) - x_obs(2, :);

plot(t_sim, err_pos, 'Color', [0.13, 0.58, 0.95], 'DisplayName', 'Position error: x_1 - xhat_1'); hold on;
plot(t_sim, err_vel*0.01, 'Color', [0.95, 0.58, 0.13], 'DisplayName', 'Scaled velocity error: 0.01 e_2');
yline(0, 'k:', 'HandleVisibility', 'off');
grid on; box on;
xlabel('Time (seconds)', 'FontWeight', 'bold');
ylabel('State Estimation Error', 'FontWeight', 'bold');
title('Figure 5: Luenberger Observer State Convergence (Poles = -120 \pm j120)', 'FontWeight', 'bold');
legend('Location', 'NorthEast');
xlim([0, 1.5]);
exportPublicationFigure(fig5, 'matlab_observer_estimation_error.png');
fprintf('Saved: matlab_observer_estimation_error.png\n\n');

% --- FIGURE 6: ROBUSTNESS ENVELOPE (8d) ---
fig6 = figure('Name', 'Robustness Envelope', 'Position', [350, 350, 800, 480], 'Color', 'w');
tt = (0:Nr-1)*Ts*1e3;
plot(tt, Yrob', 'Color', [0.7 0.7 0.7], 'HandleVisibility', 'off'); hold on;
plot(tt, mean(Yrob, 1), 'b', 'DisplayName', 'Mean of 200 perturbed plants');
yline(r_ref, 'k:', 'Setpoint', 'HandleVisibility', 'off');
grid on; box on; xlabel('Time (ms)', 'FontWeight', 'bold'); ylabel('Normalized deflection', 'FontWeight', 'bold');
title(sprintf('Figure 6: Robustness, wn +/-15%%, zeta +/-20%% (%.0f%% settled within 5%%)', 100*mean(okRob)), 'FontWeight', 'bold');
legend('Location', 'SouthEast');
exportPublicationFigure(fig6, 'matlab_robustness_envelope.png');
fprintf('Saved: matlab_robustness_envelope.png\n\n');

fprintf('====================================================================\n');
fprintf('  ALL 6 VERIFIED SIMULATION PLOTS GENERATED AND SAVED!             \n');
fprintf('====================================================================\n');

function exportPublicationFigure(fig, path)
    axesHandles = findall(fig, 'Type', 'axes');
    for idx = 1:numel(axesHandles)
        axesHandles(idx).Toolbar.Visible = 'off';
    end
    projectRoot = fileparts(mfilename('fullpath'));
    figureDir = fullfile(projectRoot, 'results', 'figures');
    if ~exist(figureDir, 'dir')
        mkdir(figureDir);
    end
    exportgraphics(fig, fullfile(figureDir, path), 'Resolution', 300);
end

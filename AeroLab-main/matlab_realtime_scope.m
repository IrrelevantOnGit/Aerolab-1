%% =========================================================================
%% AEROLAB REAL-TIME TELEMETRY / MODEL-STATE SCOPE
%% Course: Control Systems Engineering (BECE305P) | Manav Sharma (24BEC0566)
%% School of Electronics Engineering (SENSE), VIT
%% Base Paper: Araújo et al. (IEEE Access, Vol. 13, Aug. 2025)
%% =========================================================================
% Shows firmware telemetry alongside model states. The current firmware residual
% is not an independent physical actuator measurement.
%% =========================================================================

clear; close all; clc;

fprintf('====================================================================\n');
fprintf('  AEROLAB: TELEMETRY / MODEL-STATE SCOPE (MATLAB)                    \n');
fprintf('  Candidate: Manav Sharma (24BEC0566) | model/simulation scope      \n');
fprintf('====================================================================\n');

sp = [];
wifi_url = '';
mode_choice = 0; % 1=direct USB, 2=direct Wi-Fi, 3=synthetic, 4=local bridge
conn_status_label = '';
requested_mode = 'auto';
try
    target_file = fullfile(fileparts(mfilename('fullpath')), 'matlab_target.txt');
    if isfile(target_file)
        candidate_mode = lower(strtrim(fileread(target_file)));
        if any(strcmp(candidate_mode, {'auto','usb','wifi','demo'}))
            requested_mode = candidate_mode;
        end
    end
catch
end
if strcmp(requested_mode, 'demo')
    mode_choice = 3;
    conn_status_label = 'SIMULATION ONLY - explicitly selected demo; not hardware telemetry';
    fprintf('[NOTE] DEMO selected explicitly; using synthetic data, not hardware telemetry.\n');
end

% 1. FAST DETECT: Local Dashboard Bridge (relays dashboard telemetry; cadence is not inferred here)
if mode_choice == 0
try
    bridge_opt = weboptions('Timeout', 1.5);
    bridge_data = webread('http://127.0.0.1:8088/telemetry', bridge_opt);
    bridge_required = {'x1','x1_hat','y_twin','residual','cusum_sp','cusum_sm','u','servo','roll','pitch','dist2','alarm','mode'};
    bridge_fresh = isstruct(bridge_data) && isfield(bridge_data, 'age_s') && ...
        isnumeric(bridge_data.age_s) && isscalar(bridge_data.age_s) && isfinite(bridge_data.age_s) && ...
        bridge_data.age_s >= 0 && bridge_data.age_s <= 1.0 && ...
        isfield(bridge_data, 'source') && any(strcmp(string(bridge_data.source), ["ESP32_FIRMWARE", "LIVE_HARDWARE", "FIRMWARE_MANUAL_OVERRIDE"]));
    if isstruct(bridge_data) && all(isfield(bridge_data, bridge_required)) && bridge_fresh
        wifi_url = 'http://127.0.0.1:8088/telemetry';
        mode_choice = 4;
        conn_status_label = 'LIVE FIRMWARE VIA BRIDGE - host receive time; cadence unverified';
        fprintf('[OK] Locked onto Live Telemetry Stream via Local Bridge!\n');
    end
catch
end
end

% 2. FAST DETECT: ESP32 Wi-Fi Hotspot (192.168.4.1)
if mode_choice == 0
    try
        wifi_opt = weboptions('Timeout', 0.35);
        test_d = webread('http://192.168.4.1/telemetry', wifi_opt);
        live_required = {'x1','x1_hat','y_twin','residual','cusum_sp','cusum_sm','u','servo','roll','pitch','dist2','alarm','mode'};
        if isstruct(test_d) && all(isfield(test_d, live_required)) && isfield(test_d,'source') && strcmp(string(test_d.source), "ESP32_FIRMWARE")
            wifi_url = 'http://192.168.4.1/telemetry';
            mode_choice = 2;
            conn_status_label = 'LIVE FIRMWARE TELEMETRY VIA WI-FI';
            fprintf('[OK] Locked onto ESP32 Wi-Fi Hotspot!\n');
        end
    catch
    end
end

residual_threshold = 0.100;
cusum_k = 0.020;
cusum_h = 0.060;

% 3. FAST DETECT: Direct Hardware USB Serial (CP210x on COM14)
% NOTE: Avoid scanning virtual Bluetooth ports (COM3..COM13) which freeze Windows
if mode_choice == 0
    target_com = 'COM14';
    try
        sp = serialport(target_com, 460800, 'Timeout', 0.5);
        configureTerminator(sp, "LF");
        flush(sp);
        % Verify if real telemetry packets arrive within 500 ms
        t_probe = tic;
        has_bytes = false;
        while toc(t_probe) < 0.6
            if sp.NumBytesAvailable > 0
                has_bytes = true;
                break;
            end
            pause(0.02);
        end
        if has_bytes
            mode_choice = 1;
            conn_status_label = sprintf('USB packet source detected (%s @ 460800); cadence unverified', target_com);
            fprintf('[OK] Firmware packet source detected on %s; cadence not measured.\n', target_com);
        else
            delete(sp);
            sp = [];
            fprintf('[WARN] %s has no packet stream. Trying configured network source...\n', target_com);
        end
    catch
        sp = [];
    end
end

% 4. No implicit synthetic fallback: keep the scope live-ready and visibly wait.
if mode_choice == 0
    mode_choice = 4;
    wifi_url = 'http://127.0.0.1:8088/telemetry';
    conn_status_label = 'WAITING FOR FRESH LIVE TELEMETRY - select DEMO explicitly for simulation';
    fprintf('[NOTE] No live source yet; holding the plot in waiting state (no synthetic substitution).\n');
end

%% 2. CONFIGURE HIGH-DEFINITION 4-SUBPLOT CONTROL SYSTEMS FIGURE
fig = figure('Name', 'AeroLab: Telemetry and Model-State Scope', ...
             'Color', [0.03, 0.05, 0.07], ...
             'Position', [30, 30, 1240, 770], ...
             'NumberTitle', 'off');

% Subplot 1: Firmware model states / observer estimate (not independent validation)
ax1 = subplot(2, 2, 1);
set(ax1, 'Color', [0.06, 0.09, 0.12], 'XColor', [0.7, 0.8, 0.8], 'YColor', [0.7, 0.8, 0.8]);
grid on; hold on;
line_x1     = animatedline('Color', [0.13, 0.77, 0.36], 'LineWidth', 2.0, 'DisplayName', 'Firmware internal state x_1');
line_x1hat  = animatedline('Color', [0.22, 0.74, 0.97], 'LineWidth', 1.8, 'LineStyle', '--', 'DisplayName', 'Observer Estimate \hat{x}_1(t)');
line_twin   = animatedline('Color', [0.95, 0.58, 0.13], 'LineWidth', 1.5, 'LineStyle', ':', 'DisplayName', 'Model state y_{twin} (same model)');
ylabel(ax1, 'Normalized model state x_1 (0 to 1)', 'Color', [0.8, 0.9, 1.0]);
xlabel(ax1, 'Host receive elapsed time (s)', 'Color', [0.8, 0.9, 1.0]);
title(ax1, 'Model states and observer (not independent validation)', 'Color', [0.8, 0.9, 1.0], 'FontWeight', 'bold');
legend(ax1, 'Location', 'SouthEast', 'TextColor', [0.9, 0.9, 0.9]);
ylim(ax1, [-0.1, 1.25]);

% Subplot 2: Software-model residual / detector telemetry
ax2 = subplot(2, 2, 2);
set(ax2, 'Color', [0.06, 0.09, 0.12], 'XColor', [0.7, 0.8, 0.8], 'YColor', [0.7, 0.8, 0.8]);
grid on; hold on;
yyaxis(ax2, 'left');
line_res = animatedline('Color', [0.95, 0.25, 0.25], 'LineWidth', 2.0, 'DisplayName', 'Absolute residual |r(t)|');
yline(ax2, residual_threshold, 'r--', 'Residual limit δ = 0.100', ...
    'LabelHorizontalAlignment', 'left', 'LabelVerticalAlignment', 'bottom', ...
    'LineWidth', 1.3, 'Color', [1.0, 0.4, 0.4], 'HandleVisibility', 'off');
ylabel(ax2, 'Software-model residual |r|', 'Color', [0.95, 0.25, 0.25]);
yyaxis(ax2, 'right');
line_cusum = animatedline('Color', [0.98, 0.75, 0.15], 'LineWidth', 1.8, 'DisplayName', 'CUSUM S^+(t)');
line_cusum_minus = animatedline('Color', [0.25, 0.75, 0.95], 'LineWidth', 1.6, 'LineStyle', '--', 'DisplayName', 'CUSUM S^-(t)');
yline(ax2, cusum_h, 'y--', 'CUSUM limit h = 0.060', ...
    'LabelHorizontalAlignment', 'right', 'LabelVerticalAlignment', 'top', ...
    'LineWidth', 1.3, 'Color', [1.0, 0.8, 0.3], 'HandleVisibility', 'off');
title(ax2, 'Residual r(t) and CUSUM (separate scales)', 'Color', [0.8, 0.9, 1.0], 'FontWeight', 'bold');
ylabel(ax2, 'CUSUM statistic S^+, S^-', 'Color', [0.98, 0.75, 0.15]);
xlabel(ax2, 'Host receive elapsed time (s)', 'Color', [0.8, 0.9, 1.0]);
legend(ax2, [line_res, line_cusum, line_cusum_minus], 'Location', 'NorthWest', 'TextColor', [0.9, 0.9, 0.9]);
yyaxis(ax2, 'left'); ylim(ax2, [0, max(0.25, 1.1 * residual_threshold)]);
yyaxis(ax2, 'right'); ylim(ax2, [0, max(0.15, 1.1 * cusum_h)]);
ax2.YAxis(1).Color = [0.95, 0.25, 0.25];
ax2.YAxis(2).Color = [0.98, 0.75, 0.15];

% Subplot 3: Actuator Commands (LQR Effort u & Servo Position)
ax3 = subplot(2, 2, 3);
set(ax3, 'Color', [0.06, 0.09, 0.12], 'XColor', [0.7, 0.8, 0.8], 'YColor', [0.7, 0.8, 0.8]);
grid on; hold on;
line_u      = animatedline('Color', [0.65, 0.35, 0.95], 'LineWidth', 2.0, 'DisplayName', 'LQR Control Effort u(t)');
line_servo  = animatedline('Color', [0.15, 0.85, 0.85], 'LineWidth', 1.5, 'DisplayName', 'Damper Servo (\theta / 180)');
title(ax3, 'LQR effort and commanded servo', 'Color', [0.8, 0.9, 1.0], 'FontWeight', 'bold');
xlabel(ax3, 'Host receive elapsed time (s)', 'Color', [0.8, 0.9, 1.0]);
ylabel(ax3, 'Normalized Actuator Signal [0..1]', 'Color', [0.8, 0.9, 1.0]);
legend(ax3, 'Location', 'SouthEast', 'TextColor', [0.9, 0.9, 0.9]);
ylim(ax3, [-0.05, 1.15]);

% Subplot 4: Gyro-Fused Attitude & Radar Proximity Tracking
ax4 = subplot(2, 2, 4);
set(ax4, 'Color', [0.06, 0.09, 0.12], 'XColor', [0.7, 0.8, 0.8], 'YColor', [0.7, 0.8, 0.8]);
grid on; hold on;
yyaxis(ax4, 'left');
line_roll   = animatedline('Color', [0.25, 0.85, 0.55], 'LineWidth', 1.6, 'DisplayName', 'Fused Roll \phi (deg)');
line_pitch  = animatedline('Color', [0.95, 0.45, 0.25], 'LineWidth', 1.6, 'DisplayName', 'Fused Pitch \theta (deg)');
yyaxis(ax4, 'right');
line_dist2  = animatedline('Color', [0.35, 0.65, 1.00], 'LineWidth', 1.4, 'DisplayName', 'Servo-mounted US2 range (cm)');
title(ax4, 'Accelerometer-derived tilt and servo US2 range', 'Color', [0.8, 0.9, 1.0], 'FontWeight', 'bold');
xlabel(ax4, 'Host receive elapsed time (s)', 'Color', [0.8, 0.9, 1.0]);
yyaxis(ax4, 'left'); ylabel(ax4, 'Tilt (deg)', 'Color', [0.8, 0.9, 1.0]);
yyaxis(ax4, 'right'); ylabel(ax4, 'US2 range (cm)', 'Color', [0.8, 0.9, 1.0]);
legend(ax4, 'Location', 'NorthEast', 'TextColor', [0.9, 0.9, 0.9]);
yyaxis(ax4, 'left'); ylim(ax4, [-60, 60]);
yyaxis(ax4, 'right'); ylim(ax4, [0, 200]);

% Banner Annotations for Real-Time Status & Diagnostics
if mode_choice == 3
    initial_status_label = 'SIMULATION ONLY';
elseif mode_choice == 4 && contains(conn_status_label, 'WAITING')
    initial_status_label = 'WAITING FOR LIVE TELEMETRY';
else
    initial_status_label = 'STREAMING ACTIVE';
end
status_box = annotation('textbox', [0.03, 0.005, 0.94, 0.045], ...
    'String', sprintf('[%s] %s', initial_status_label, conn_status_label), ...
    'FontWeight', 'bold', 'FontSize', 11, ...
    'HorizontalAlignment', 'center', ...
    'Color', [0.2, 1.0, 0.4], ...
    'BackgroundColor', [0.05, 0.10, 0.15], ...
    'EdgeColor', [0.2, 0.7, 0.9]);

% Bring figure to front immediately
figure(fig);
drawnow;

%% 3. TELEMETRY RENDERING LOOP (device cadence not inferred from host receive time)
fprintf('\nStreaming real-time telemetry into MATLAB figure window...\n');
fprintf('Active Mode: %s\n', conn_status_label);
fprintf('Time axis is host receive elapsed time; live device cadence is not measured here.\n');
fprintf('Close figure window or press Ctrl+C in console to stop.\n\n');

web_opt_fast = weboptions('Timeout', 0.50);   % created once (was rebuilt 20x/s = slow)
t_start = tic;
max_history_sec = 25.0;
consecutive_serial_misses = 0;
demo_frame_index = 0;
demo_sample(0, 'reset', hex2dec('A3E01234'));

cleanupObj = onCleanup(@() cleanupResources(sp));

while isvalid(fig)
    t_now = toc(t_start);
    plot_time = t_now;
    data = [];
    
    if mode_choice == 1
        % Direct USB Serial Read from COM14
        if sp.NumBytesAvailable > 0
            consecutive_serial_misses = 0;
            raw_str = strtrim(readline(sp));
            if startsWith(raw_str, '{') && endsWith(raw_str, '}')
                try
                    data = jsondecode(raw_str);
                catch
                    continue;
                end
            else
                continue;
            end
        else
            consecutive_serial_misses = consecutive_serial_misses + 1;
            if consecutive_serial_misses > 40
                conn_status_label = 'USB TELEMETRY STALE - awaiting firmware packets; no synthetic substitution';
                set(status_box, 'String', '[STALE USB] No packet received; live view paused until telemetry resumes.', ...
                    'Color', [1.0, 0.25, 0.25]);
            end
            pause(0.01);
            continue;
        end
    elseif mode_choice == 2 || mode_choice == 4
        % HTTP Telemetry Read (Local Bridge or Wi-Fi Hotspot)
        try
            data = webread(wifi_url, web_opt_fast);
            if ischar(data) || isstring(data)
                data = jsondecode(data);
            end
        catch
            set(status_box, 'String', '[STALE NETWORK] No fresh packet; live view paused (no demo substitution).', 'Color', [1.0, 0.25, 0.25]);
            drawnow limitrate;
            pause(0.04);
            continue;
        end
    else
        % Mode 3: illustrative synthetic software simulation
        pause(0.05);
        demo_frame_index = demo_frame_index + 1;
        sim_t = demo_frame_index * 0.05;
        plot_time = sim_t;
        
        % Shared production demo frame; exact sample-index time and seeded state.
        data = demo_sample(sim_t);
    end
    
    required_fields = {'x1','x1_hat','y_twin','residual','cusum_sp','cusum_sm','u','servo','roll','pitch','dist2','mode','alarm'};
    packet_valid = ~isempty(data) && isstruct(data) && all(isfield(data, required_fields));
    if packet_valid
        packet_valid = all(cellfun(@(f) isnumeric(data.(f)) && isscalar(data.(f)) && isfinite(data.(f)), required_fields));
    end
    if ~packet_valid
        set(status_box, 'String', '[INVALID TELEMETRY] Packet incomplete; refusing to plot as live data.', 'Color', [1.0, 0.25, 0.25]);
        drawnow limitrate;
        continue;
    end
    if mode_choice ~= 3 && ~all(cellfun(@(f) isnumeric(data.(f)) && isscalar(data.(f)) && isfinite(data.(f)), required_fields))
        set(status_box, 'String', '[INVALID TELEMETRY] Non-finite/nonnumeric values rejected.', 'Color', [1.0, 0.25, 0.25]);
        drawnow limitrate;
        continue;
    end
    if mode_choice == 1 && (~isfield(data,'source') || ~strcmp(data.source,'ESP32_FIRMWARE'))
        set(status_box, 'String', '[INVALID SOURCE] USB packet lacks firmware provenance.', 'Color', [1.0, 0.25, 0.25]);
        drawnow limitrate;
        continue;
    end
    if any(mode_choice == [2, 4]) && isfield(data,'source') && strcmp(data.source,'SIMULATION_ONLY')
        set(status_box, 'String', '[INVALID SOURCE] Simulation packet rejected by live link.', 'Color', [1.0, 0.25, 0.25]);
        drawnow limitrate;
        continue;
    end
    if mode_choice == 3
            set(status_box, 'String', '[SIMULATION ONLY] Synthetic trajectory — not hardware telemetry.', 'Color', [1.0, 0.65, 0.1]);
    elseif any(mode_choice == [1, 4]) && isfield(data,'manualOverride') && data.manualOverride ~= 0
        set(status_box, 'String', '[FIRMWARE MANUAL OVERRIDE] Not an unmodified sensor measurement.', 'Color', [1.0, 0.65, 0.1]);
    elseif any(mode_choice == [1, 2, 4])
        set(status_box, 'String', sprintf('[LIVE HARDWARE] %s', conn_status_label), 'Color', [0.2, 1.0, 0.4]);
    end
    if mode_choice == 4 && strcmp(wifi_url, 'http://127.0.0.1:8088/telemetry')
        % Bridge returns "_age" which becomes "x_age" in MATLAB jsondecode
        age_val = NaN;
        if isfield(data, 'x_age') && isnumeric(data.x_age) && isscalar(data.x_age)
            age_val = data.x_age;
        elseif isfield(data, 'age_s') && isnumeric(data.age_s) && isscalar(data.age_s)
            age_val = data.age_s;
        end
        if ~isfinite(age_val) || age_val < 0 || age_val > 1.0 || ~isfield(data,'source') || ...
                ~any(strcmp(string(data.source), ["ESP32_FIRMWARE", "LIVE_HARDWARE", "FIRMWARE_MANUAL_OVERRIDE"]))
            set(status_box, 'String', '[STALE/UNVERIFIED TELEMETRY] Bridge data missing freshness or hardware provenance; not presented as live.', 'Color', [1.0, 0.25, 0.25]);
            drawnow limitrate;
            pause(0.05);
            continue;
        end
    end
    if mode_choice == 2 && strcmp(wifi_url, 'http://192.168.4.1/telemetry') && ...
            (~isfield(data,'source') || ~strcmp(string(data.source), "ESP32_FIRMWARE"))
        set(status_box, 'String', '[UNVERIFIED SOURCE] Wi-Fi packet lacks firmware provenance.', 'Color', [1.0, 0.25, 0.25]);
        drawnow limitrate;
        continue;
    end
    if mode_choice == 2 && strcmp(wifi_url, 'http://192.168.4.1/telemetry') && ...
            isfield(data,'age_s') && (~isnumeric(data.age_s) || ~isscalar(data.age_s) || ~isfinite(data.age_s) || data.age_s < 0 || data.age_s > 1.0)
        set(status_box, 'String', '[STALE WI-FI] Packet age exceeds 1 s; refusing to plot.', 'Color', [1.0, 0.25, 0.25]);
        drawnow limitrate;
        continue;
    end
    
    % Extract signals
    x1_val    = double(data.x1);
    x1hat_val = double(data.x1_hat);
    twin_val  = double(data.y_twin);
    res_val   = double(data.residual);
    cusum_val = double(data.cusum_sp);
    cusum_minus_val = double(data.cusum_sm);
    u_val     = double(data.u);
    servo_val = double(data.servo) / 180.0;
    roll_val  = double(data.roll);
    pitch_val = double(data.pitch);
    % US2 is the servo-mounted proximity ranger; its units use the right axis.
    dist2_val = double(data.dist2);
    % A 999 cm sentinel or stale/missing echo is not a measurement. Break the
    % range trace with NaN until the servo-mounted sensor reports a fresh echo.
    if mode_choice == 3
        us2_live_fresh = true;
    elseif isfield(data,'us2EchoOk') && isfield(data,'us2AgeMs')
        us2_live_fresh = double(data.us2EchoOk) == 1 && isfinite(double(data.us2AgeMs)) && ...
                double(data.us2AgeMs) >= 0 && double(data.us2AgeMs) <= 300 && dist2_val >= 2 && dist2_val <= 200;
    else
        % Missing echo-health metadata is not evidence of a fresh range, on
        % USB, Wi-Fi, or bridge transports alike.
        us2_live_fresh = false;
    end
    if ~us2_live_fresh
        dist2_val = NaN;
    end
    
    % Append points to animated lines
    addpoints(line_x1,    plot_time, x1_val);
    addpoints(line_x1hat, plot_time, x1hat_val);
    addpoints(line_twin,  plot_time, twin_val);
    
    % Scale each detector in its own units and include the entire visible
    % history so an earlier CUSUM peak remains visible as it decays.
    yyaxis(ax2, 'left');
    addpoints(line_res, plot_time, res_val);
    ylim(ax2, [0, max(0.25, 1.1 * max([res_val, residual_threshold]))]);
    yyaxis(ax2, 'right');
    addpoints(line_cusum, plot_time, cusum_val);
    addpoints(line_cusum_minus, plot_time, cusum_minus_val);
    [cusum_t, cusum_y] = getpoints(line_cusum);
    [cusum_minus_t, cusum_minus_y] = getpoints(line_cusum_minus);
    visible_cusum = [cusum_y(cusum_t >= plot_time - max_history_sec), ...
                     cusum_minus_y(cusum_minus_t >= plot_time - max_history_sec)];
    ylim(ax2, [0, max(0.15, 1.1 * max([visible_cusum, cusum_h]))]);
    
    addpoints(line_u,     plot_time, u_val);
    addpoints(line_servo, plot_time, servo_val);
    
    yyaxis(ax4, 'left');
    addpoints(line_roll,  plot_time, roll_val);
    addpoints(line_pitch, plot_time, pitch_val);
    yyaxis(ax4, 'right');
    addpoints(line_dist2, plot_time, dist2_val);
    
    % Sliding axis (25-second rolling observation window)
    x_min = max(0, plot_time - max_history_sec);
    x_max = max(max_history_sec, plot_time);
    xlim(ax1, [x_min, x_max]);
    xlim(ax2, [x_min, x_max]);
    xlim(ax3, [x_min, x_max]);
    xlim(ax4, [x_min, x_max]);
    
    % Dynamic status banner
    mode_names = {'HUD', 'Hand scan', 'Radar sweep', ...
                  'LQR demo', 'Step test', 'IMU gimbal'};
    cur_mode = min(max(double(data.mode), 0), 5) + 1;
    
    alarm_col = [0.2, 1.0, 0.4];
    alarm_tag = 'NOMINAL';
    if data.alarm == 2
        alarm_col = [1.0, 0.25, 0.25];
        alarm_tag = 'RED ALARM';
    elseif data.alarm == 1
        alarm_col = [1.0, 0.75, 0.20];
        alarm_tag = 'YELLOW CAUTION';
    end
    
    provenance = 'LIVE STREAM';
    if mode_choice == 1
        provenance = 'LIVE USB';
    elseif mode_choice == 2
        provenance = 'LIVE WI-FI';
    elseif mode_choice == 4
        provenance = 'LIVE BRIDGE';
    elseif isfield(data, 'source')
        provenance = char(string(data.source));
    end
    if mode_choice == 3
        provenance = 'SIMULATION ONLY';
        alarm_col = [1.0, 0.65, 0.1];
    elseif isfield(data, 'manualOverride') && double(data.manualOverride) ~= 0
        provenance = 'MANUAL OVERRIDE';
        alarm_col = [1.0, 0.65, 0.1];
    end
    reason_short = '';
    if isfield(data, 'reason') && ~isempty(data.reason)
        reason_short = char(string(data.reason));
    end
    us2_token = regexp(reason_short, 'US2\)=([0-9.]+cm)', 'tokens', 'once');
    if ~isempty(us2_token)
        reason_short = ['US2=' us2_token{1} ' RED'];
    elseif numel(reason_short) > 18
        reason_short = [reason_short(1:15), '...'];
    end
    if mode_choice == 3
        range_short = sprintf('SIM US2=%.1fcm', dist2_val);
    elseif us2_live_fresh
        raw_us2 = NaN;
        if isfield(data,'us2RawCm') && isnumeric(data.us2RawCm) && isscalar(data.us2RawCm)
            raw_us2 = double(data.us2RawCm);
        end
        if isfinite(raw_us2) && raw_us2 >= 2.0 && raw_us2 < 5.0
            range_short = sprintf('US2 VERY CLOSE raw %.1fcm; filtered %.1fcm — VERIFY', raw_us2, dist2_val);
        elseif isfinite(raw_us2)
            range_short = sprintf('US2 raw %.1f / filtered %.1fcm', raw_us2, dist2_val);
        else
            range_short = sprintf('US2 %.1fcm', dist2_val);
        end
    else
        range_short = 'US2 NO FRESH ECHO';
    end
    status_str = sprintf('[%s] %s | %s | r=%.3f | S+=%.2f S-=%.2f | %s', ...
        alarm_tag, provenance, ...
        range_short, res_val, cusum_val, cusum_minus_val, reason_short);
    set(status_box, 'String', status_str, 'Color', alarm_col);
    
    drawnow limitrate;
end

function cleanupResources(sp)
    if ~isempty(sp) && isvalid(sp)
        delete(sp);
        fprintf('\n[CLEANUP] Serial port closed and released cleanly.\n');
    end
end


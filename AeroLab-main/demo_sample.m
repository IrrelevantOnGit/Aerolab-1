function data = demo_sample(t, action, seed)
%DEMO_SAMPLE Shared deterministic illustrative telemetry frame for MATLAB scope.
% Call demo_sample(0, 'reset', seed) to reset noise and detector accumulators.
% This signal is synthetic software data, not a physical plant measurement.
persistent s_plus s_minus
if nargin >= 2 && strcmpi(action, 'reset')
    if nargin < 3, seed = hex2dec('A3E01234'); end
    demo_noise('reset', seed);
    s_plus = 0;
    s_minus = 0;
    data = struct();
    return;
end
if isempty(s_plus), s_plus = 0; s_minus = 0; end

cycle = mod(t, 8);
reference = 0.25;
if cycle >= 4, reference = 0.85; end
dt = mod(cycle, 4);
phase = mod(t, 48);
drift = 0.145 * (phase >= 12 && phase <= 18) - ...
    0.145 * (phase >= 36 && phase <= 42);
nominal = reference - 0.035 * exp(-5.2 * dt) * cos(14.2 * dt);
x1 = nominal + drift + 0.003 * demo_noise();
y_twin = nominal + 0.003 * demo_noise();
x1_hat = x1 * 0.99 + 0.002 * demo_noise();
signed_residual = x1 - y_twin;
residual = abs(signed_residual);
s_plus = max(0, s_plus + signed_residual - 0.020);
s_minus = max(0, s_minus - signed_residual - 0.020);
roll = 1.8 * sin(0.9 * t);
alarm = 0;
reason = 'SIMULATED MODEL STATES';
if residual > 0.100 || max(s_plus, s_minus) >= 0.060
    alarm = 2;
    reason = 'SYNTHETIC MODEL OFFSET: residual/CUSUM limit exceeded';
elseif abs(roll) > 12
    alarm = 1;
    reason = 'SYNTHETIC ATTITUDE EVENT';
end

data = struct('source', 'SIMULATION_ONLY', 'x1', x1, 'x1_hat', x1_hat, ...
    'y_twin', y_twin, 'residual', residual, 'cusum_sp', s_plus, ...
    'cusum_sm', s_minus, 'u', max(0, min(1, 0.58 * reference + ...
    0.30 * (x1_hat - reference))), 'servo', round(x1 * 180), ...
    'roll', roll, 'pitch', x1 * 15 - 7.5, ...
    'dist2', 50 + 25 * cos(0.4 * t), 'mode', 3, 'alarm', alarm, ...
    'reason', reason, 'temp', 28.5 + 0.5 * sin(0.1 * t), 'heap', 182000);
end

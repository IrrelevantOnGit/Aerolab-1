function z = demo_noise(action, seed)
%DEMO_NOISE Shared deterministic xorshift32/Box-Muller noise for demo traces.
% Reset with demo_noise('reset', hex2dec('A3E01234')). This is illustrative
% synthetic data only; it is not a physical sensor or plant noise model.
persistent state
if nargin > 0 && strcmpi(action, 'reset')
    state = uint32(seed);
    z = 0;
    return;
end
if isempty(state)
    state = uint32(hex2dec('A3E01234'));
end
[u1, state] = uniform32(state);
[u2, state] = uniform32(state);
z = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
end

function [u, state] = uniform32(state)
state = bitxor(state, bitshift(state, 13));
state = bitxor(state, bitshift(state, -17));
state = bitxor(state, bitshift(state, 5));
u = (double(state) + 0.5) / 4294967296.0;
end

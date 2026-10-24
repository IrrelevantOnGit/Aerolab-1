% MATLAB-side golden checks for the shared synthetic demo signal contract.
% Run from the project root with: matlab -batch "run('test/matlab_demo_contract_test.m')"
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
seed = hex2dec('A3E01234');
expectedNoise = [-0.9434264076355248, 0.1615249851130549, 1.1813874691482749, ...
    0.46748576490670124, 0.9034912155885615, 0.03947312977731734];
demo_sample(0, 'reset', seed);
actualNoise = zeros(size(expectedNoise));
for k = 1:numel(actualNoise), actualNoise(k) = demo_noise(); end
assert(max(abs(actualNoise - expectedNoise)) < 1e-12, ...
    'MATLAB demo RNG vector differs from the cross-scope contract.');

demo_sample(0, 'reset', seed);
expected = [0.22670395632875273, 0.23001881050699846, 0.22679969170376174, ...
    0.0033148541782457297, 0.13803990751112852; ...
    0.24827653279053596, 0.24958454914258155, 0.24587271372218522, ...
    0.0013080163520455823, 0.14376181411665556; ...
    0.25970138359194733, 0.2561467726704296, 0.25557384424463697, ...
    0.003554610921517709, 0.1466721532733911];
for k = 1:size(expected, 1)
    frame = demo_sample(k * 0.05);
    actual = [frame.x1, frame.y_twin, frame.x1_hat, frame.residual, frame.u];
    assert(max(abs(actual - expected(k, :))) < 1e-12, ...
        'MATLAB demo frame %d differs from the JavaScript/Python golden vector.', k);
end
fprintf('MATLAB demo RNG and first three frame golden tests passed.\n');

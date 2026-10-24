// Focused regressions for dashboard telemetry and chart handling.
// Run with: node test/dashboard_scope_test.js
'use strict';
const assert = require('node:assert/strict');
const { finitePairSegments, demoFrame, ultrasonicDiagnostic, freshUltrasonic, liveUltrasonicRangeValid, modelSignals } = require('../dashboard_scope_logic.js');

function classifyRange({ echoOk, ageMs, filteredCm, rawCm }) {
  const fresh = !!echoOk && Number.isFinite(ageMs) && ageMs >= 0 && ageMs <= 300 &&
    Number.isFinite(filteredCm) && filteredCm >= 2 && filteredCm <= 200;
  if (!fresh) return { status: 'NO FRESH ECHO', usable: false };
  if (Number.isFinite(rawCm) && rawCm < 5)
    return { status: 'VERY CLOSE · VERIFY', usable: true, alarm: rawCm < 14 ? 'CRITICAL' : 'CAUTION' };
  return { status: `${filteredCm.toFixed(1)} cm`, usable: true,
    alarm: filteredCm < 14 ? 'CRITICAL' : filteredCm < 28 ? 'CAUTION' : 'NOMINAL' };
}

assert.deepEqual(classifyRange({ echoOk: 1, ageMs: 25, filteredCm: 3.9, rawCm: 3.88 }),
  { status: 'VERY CLOSE · VERIFY', usable: true, alarm: 'CRITICAL' });
assert.deepEqual(classifyRange({ echoOk: 1, ageMs: null, filteredCm: 0, rawCm: null }),
  { status: 'NO FRESH ECHO', usable: false });
assert.equal(classifyRange({ echoOk: 1, ageMs: 20, filteredCm: 22, rawCm: 22 }).alarm, 'CAUTION');
assert.equal(classifyRange({ echoOk: 1, ageMs: 20, filteredCm: 52, rawCm: 52 }).alarm, 'NOMINAL');
assert.equal(classifyRange({ echoOk: 1, ageMs: 20, filteredCm: 149, rawCm: 149 }).alarm, 'NOMINAL',
  'clear-space echo above the former 120 cm limit remains fresh');
function aggregateUltrasonicAlarm({ critical, caution, us1Fresh, us2Fresh }) {
  if (critical) return 'CRITICAL';
  if (caution || !us1Fresh || !us2Fresh) return 'CAUTION';
  return 'NOMINAL';
}
assert.equal(aggregateUltrasonicAlarm({ critical: true, caution: false, us1Fresh: true, us2Fresh: true }), 'CRITICAL');
assert.equal(aggregateUltrasonicAlarm({ critical: false, caution: false, us1Fresh: true, us2Fresh: false }), 'CAUTION');
assert.equal(aggregateUltrasonicAlarm({ critical: false, caution: false, us1Fresh: true, us2Fresh: true }), 'NOMINAL');

function scopeRangeStatus({ source, echoOk, ageMs, filteredCm, rawCm }) {
  if (source === 'SIMULATION_ONLY') return `SIM US2 ${filteredCm.toFixed(1)} cm`;
  if (echoOk !== 1 || !Number.isFinite(ageMs) || ageMs < 0 || ageMs > 300 ||
      !Number.isFinite(filteredCm) || filteredCm < 2 || filteredCm > 200)
    return 'US2 NO FRESH ECHO';
  if (Number.isFinite(rawCm) && rawCm >= 2 && rawCm < 5)
    return `US2 VERY CLOSE raw ${rawCm.toFixed(1)} / filtered ${filteredCm.toFixed(1)} cm — VERIFY`;
  if (Number.isFinite(rawCm)) return `US2 raw ${rawCm.toFixed(1)} / filtered ${filteredCm.toFixed(1)} cm`;
  return `US2 ${filteredCm.toFixed(1)} cm`;
}
assert.match(scopeRangeStatus({ source: 'ESP32_FIRMWARE', echoOk: 1, ageMs: 30, rawCm: 3.88, filteredCm: 3.9 }), /VERY CLOSE.*VERIFY/);
assert.equal(scopeRangeStatus({ source: 'ESP32_FIRMWARE', echoOk: 1, ageMs: 301, rawCm: 52, filteredCm: 52 }), 'US2 NO FRESH ECHO');
assert.equal(scopeRangeStatus({ source: 'ESP32_FIRMWARE', echoOk: 0, ageMs: 30, rawCm: 3.88, filteredCm: 3.9 }), 'US2 NO FRESH ECHO');
assert.equal(scopeRangeStatus({ source: 'SIMULATION_ONLY', echoOk: 0, ageMs: null, rawCm: null, filteredCm: 75 }), 'SIM US2 75.0 cm');
assert.equal(scopeRangeStatus({ source: 'ESP32_FIRMWARE', echoOk: 1, ageMs: 30, rawCm: 149, filteredCm: 149 }),
  'US2 raw 149.0 / filtered 149.0 cm', 'scope status accepts clear-space readings above 120 cm');

// Firmware scan acquisition must agree with the configured sensor minimum and
// must include the critical-near band; close-range alarms remain independent.
const ULTRASONIC_MIN_RELIABLE_CM = 2.0, HAND_SCAN_MAX_CM = 55.0;
function scanHasTarget({ fresh, newSample, distanceCm }) {
  return !!fresh && !!newSample && distanceCm >= ULTRASONIC_MIN_RELIABLE_CM && distanceCm <= HAND_SCAN_MAX_CM;
}
assert.equal(scanHasTarget({ fresh: true, newSample: true, distanceCm: 3.9 }), true, 'close target remains trackable during critical alarm');
assert.equal(scanHasTarget({ fresh: true, newSample: true, distanceCm: 1.5 }), false, 'below-range echo is rejected');
assert.equal(scanHasTarget({ fresh: true, newSample: true, distanceCm: 56 }), false, 'background beyond scan limit is rejected');
assert.equal(scanHasTarget({ fresh: false, newSample: false, distanceCm: 30 }), false, 'stale return cannot acquire a target');
assert.equal(scanHasTarget({ fresh: true, newSample: false, distanceCm: 3.9 }), false, 'cached close sample cannot refresh acquisition');

function broadReturn(samples, hits, threshold = 0.65) {
  return samples >= 8 && hits <= samples && hits / samples >= threshold;
}
assert.equal(broadReturn(18, 18), true, 'a near return spanning the scan is not localized hand evidence');
assert.equal(broadReturn(18, 3), false, 'a localized scan return remains a candidate');

// The chart renderer must ignore missing samples while autoscaling and break
// the line at missing samples instead of coercing them to zero.
assert.deepEqual(finitePairSegments([.2, null, .4, .5], [1, 2, .3, .2]),
  [[[.2, 1, 0]], [[.4, .3, 2], [.5, .2, 3]]]);
assert.deepEqual(finitePairSegments([.2, .3], [null, NaN]), []);
assert.equal(ultrasonicDiagnostic({us1Diagnostic:0,us1PulseUs:0},'us1'),'TIMEOUT (0 us)');
assert.equal(ultrasonicDiagnostic({us2Diagnostic:1,us2PulseUs:583},'us2'),'ECHO 10.0 cm (583 us)');
assert.equal(ultrasonicDiagnostic({us2Diagnostic:3,us2PulseUs:12000},'us2'),'OUTSIDE 2–200 cm (205.8 cm)');
assert.equal(freshUltrasonic({us1EchoOk:1,us1AgeMs:40,dist1:199.2},'us1'),true,
  'valid clear-space return near 200 cm is fresh telemetry, not a timeout sentinel');
assert.equal(freshUltrasonic({us2EchoOk:0,us2AgeMs:0,dist2:999},'us2'),false,
  'distinct no-echo sentinel is never treated as a real measurement');
assert.equal(liveUltrasonicRangeValid({us1EchoOk:1,us1AgeMs:40,dist1:149},'us1'),true,
  'shared live range contract accepts a fresh 149 cm reading');
assert.equal(liveUltrasonicRangeValid({us2EchoOk:1,us2AgeMs:40,dist2:200},'us2'),true,
  'shared live range contract accepts the upper 200 cm boundary');
assert.equal(liveUltrasonicRangeValid({us2EchoOk:1,us2AgeMs:40,dist2:200.1},'us2'),false,
  'shared live range contract rejects values beyond configured sensor range');
assert.equal(liveUltrasonicRangeValid({us2EchoOk:1,us2AgeMs:-1,dist2:30},'us2'),false,
  'negative sample age is not fresh telemetry');
const absentModel=modelSignals({servo:90});
assert.equal(absentModel.servo,.5,'commanded servo is available as a distinct actuator trace');
for(const key of ['x1','twin','observer','residual','cusumPlus','cusumMinus','effort','x2','roll','pitch','temp','adaptiveThreshold'])
  assert.equal(absentModel[key],null,`missing ${key} remains a plot gap; it must not become a synthetic value`);
assert.deepEqual(modelSignals({x1:.2,y_twin:.21,x1_hat:.19,residual:.01,cusum_sp:.02,cusum_sm:0,u:.4,servo:72,x2:-.1,roll:1,pitch:2,temp:25,adaptThresh:38}),
  {x1:.2,twin:.21,observer:.19,residual:.01,cusumPlus:.02,cusumMinus:0,effort:.4,servo:.4,x2:-.1,roll:1,pitch:2,temp:25,adaptiveThreshold:38},
  'all actual firmware model values map with their units/meaning preserved');

// The production Python/MATLAB consumers use a matching 2–200 cm contract.
// Keep the bounded range predicate itself canonical above and assert the source
// bounds here so a later narrowing cannot pass the demo-only golden tests.
const fs = require('node:fs');
const pyScope = fs.readFileSync(require.resolve('../python_realtime_scope.py'), 'utf8');
const matlabScope = fs.readFileSync(require.resolve('../matlab_realtime_scope.m'), 'utf8');
const dashboard = fs.readFileSync(require.resolve('../dashboard.html'), 'utf8');
const analytics = fs.readFileSync(require.resolve('../dashboard_analytics.html'), 'utf8');
assert.match(pyScope, /math\.isfinite\(raw\) and 2 <= raw <= 200/,
  'Python live scope must plot valid returns through 200 cm');
assert.match(matlabScope, /dist2_val >= 2 && dist2_val <= 200/,
  'MATLAB live scope must plot valid returns through 200 cm');
assert.match(matlabScope, /bridge_data\.age_s >= 0 && bridge_data\.age_s <= 1\.0/,
  'MATLAB bridge must reject negative receive age');
for(const [name,source] of [['main',dashboard],['analytics',analytics]]){
  assert.match(source,/d\._age>=0&&d\._age<=1\.0/,`${name} dashboard rejects future-dated bridge packets`);
  assert.match(source,/AeroLabScopeLogic\.modelSignals\(d\)/,`${name} dashboard plots actual model fields without defaults`);
  assert.doesNotMatch(source,/d\.y_twin\s*\?\?\s*x1_val|d\.cusum_sp\s*\?\?\s*0|d\.u\s*\?\?\s*0\.5/,`${name} dashboard has no invented live model trace fallbacks`);
}

function close(actual, want, name) { assert.ok(Math.abs(actual - want) < 1e-12, `${name}: ${actual} != ${want}`); }
const demoState={rng:0xA3E01234,Splus:0,Sminus:0};
const expectedFrames=[
  {x1:.22670395632875273,y_twin:.23001881050699846,x1_hat:.22679969170376174,residual:.0033148541782457297,u:.13803990751112852},
  {x1:.24827653279053596,y_twin:.24958454914258155,x1_hat:.24587271372218522,residual:.0013080163520455823,u:.14376181411665556},
  {x1:.25970138359194733,y_twin:.2561467726704296,x1_hat:.25557384424463697,residual:.003554610921517709,u:.1466721532733911}
];
for (const [i,t] of [.05,.1,.15,.2,.25,.3,.35,.4,.45,.5,.55,.6].entries()) {
  const f=demoFrame(t,demoState);
  if(i<expectedFrames.length)for(const [key,want] of Object.entries(expectedFrames[i]))close(f[key],want,`demo frame ${i+1} ${key}`);
  for(const v of Object.values(f))assert.ok(Number.isFinite(v),`finite demo output at frame ${i}`);
}
console.log('dashboard telemetry/range and scope-gap regressions passed');

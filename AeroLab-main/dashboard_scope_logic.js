/* Shared production chart helpers; also imported directly by Node regressions. */
(function (root) {
  'use strict';
  function finitePairSegments(xs, ys) {
    const segments = [];
    let active = [];
    const n = Math.min(xs.length, ys.length);
    for (let i = 0; i < n; i++) {
      const x = xs[i], y = ys[i];
      if (typeof x !== 'number' || !Number.isFinite(x) ||
          typeof y !== 'number' || !Number.isFinite(y)) {
        if (active.length) segments.push(active);
        active = [];
      } else active.push([x, y, i]);
    }
    if (active.length) segments.push(active);
    return segments;
  }
  function uniform32(state) {
    let x=state.rng>>>0;
    x=(x^(x<<13))>>>0; x=(x^(x>>>17))>>>0; x=(x^(x<<5))>>>0;
    state.rng=x;
    return (x+0.5)/4294967296;
  }
  function normal(state) {
    const u1=Math.max(Number.MIN_VALUE,uniform32(state)),u2=uniform32(state);
    return Math.sqrt(-2*Math.log(u1))*Math.cos(2*Math.PI*u2);
  }
  function demoFrame(t,state) {
    const cycle=t%8,reference=cycle<4?.25:.85,dt=cycle%4,phase=t%48;
    const drift=phase>=12&&phase<=18?.145:phase>=36&&phase<=42?-.145:0;
    const nominal=reference-.035*Math.exp(-5.2*dt)*Math.cos(14.2*dt);
    const x1=nominal+drift+.003*normal(state), twin=nominal+.003*normal(state);
    const x1hat=x1*.99+.002*normal(state), signed=x1-twin;
    state.Splus=Math.max(0,state.Splus+signed-.02);
    state.Sminus=Math.max(0,state.Sminus-signed-.02);
    const residual=Math.abs(signed),roll=1.8*Math.sin(.9*t);
    return {reference,x1,y_twin:twin,x1_hat:x1hat,residual,Splus:state.Splus,Sminus:state.Sminus,
      u:Math.max(0,Math.min(1,.58*reference+.3*(x1hat-reference))),servo:Math.round(x1*180),
      roll,pitch:15*x1-7.5,dist2:50+25*Math.cos(.4*t),
      alarm:residual>.1||state.Splus>=.06||state.Sminus>=.06?2:Math.abs(roll)>12?1:0};
  }
  function ultrasonicDiagnostic(packet,prefix) {
    const code=packet[`${prefix}Diagnostic`],pulse=packet[`${prefix}PulseUs`];
    const hasPulse=typeof pulse==='number'&&Number.isFinite(pulse),cm=hasPulse?pulse*.0343/2:NaN;
    if(code===0)return `TIMEOUT (${hasPulse?pulse:0} us)`;
    if(code===1)return `ECHO ${cm.toFixed(1)} cm (${pulse} us)`;
    if(code===2)return `TOO CLOSE (${cm.toFixed(1)} cm)`;
    if(code===3)return `OUTSIDE 2–200 cm (${cm.toFixed(1)} cm)`;
    if(code===4)return 'MANUAL OVERRIDE';
    return 'NO DIAGNOSTIC';
  }
  function freshUltrasonic(packet,prefix) {
    const echo=packet[`${prefix}EchoOk`],age=packet[`${prefix}AgeMs`],distance=packet[prefix==='us1'?'dist1':'dist2'];
    return echo===1&&typeof age==='number'&&Number.isFinite(age)&&age>=0&&age<=300&&
      typeof distance==='number'&&Number.isFinite(distance)&&distance>=2&&distance<=200;
  }
  function liveUltrasonicRangeValid(packet,prefix) {
    const echo=packet[`${prefix}EchoOk`],age=packet[`${prefix}AgeMs`],distance=packet[prefix==='us1'?'dist1':'dist2'];
    return echo===1&&typeof age==='number'&&Number.isFinite(age)&&age>=0&&age<=300&&
      typeof distance==='number'&&Number.isFinite(distance)&&distance>=2&&distance<=200;
  }
  function modelSignals(packet) {
    const value = key => typeof packet[key] === 'number' && Number.isFinite(packet[key]) ? packet[key] : null;
    const servo = value('servo');
    return {
      x1: value('x1'), twin: value('y_twin'), observer: value('x1_hat'),
      residual: value('residual'), cusumPlus: value('cusum_sp'), cusumMinus: value('cusum_sm'),
      effort: value('u'), servo: servo === null ? null : servo / 180,
      x2: value('x2'), roll: value('roll'), pitch: value('pitch'),
      temp: value('temp'), adaptiveThreshold: value('adaptThresh')
    };
  }
  const api = { finitePairSegments, demoFrame, ultrasonicDiagnostic, freshUltrasonic, liveUltrasonicRangeValid, modelSignals };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.AeroLabScopeLogic = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);

// Host test of the firmware control law (no hardware needed):  g++ -std=c++17 -I.. test/host_control_test.cpp -o t && ./t
#include <cstdio>
#include <cmath>
#include "../gnc_core.h"
#include "../gnc_gains.h"
static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { ++fails; std::printf("FAIL: " __VA_ARGS__); std::printf("\n"); } } while (0)
struct Loop { // identical equations to stepControlAndObserver() in main.cpp
  float x1 = .5f, x2 = 0, h1 = .5f, h2 = 0, t1 = .5f, t2 = 0, u = 0;
  void tick(float r, float y) {
    float e = y - h1; h1 += gains::L[0] * e; h2 += gains::L[1] * e;
    u = fminf(1.f, fmaxf(0.f, gains::Nbar * r - (gains::K[0] * h1 + gains::K[1] * h2)));
    for (int i = 0; i < 50; i++) {
      float a = gains::Af[0][0]*x1 + gains::Af[0][1]*x2 + gains::Bf[0]*u, b = gains::Af[1][0]*x1 + gains::Af[1][1]*x2 + gains::Bf[1]*u; x1 = a; x2 = b;
      a = gains::Af[0][0]*t1 + gains::Af[0][1]*t2 + gains::Bf[0]*u; b = gains::Af[1][0]*t1 + gains::Af[1][1]*t2 + gains::Bf[1]*u; t1 = a; t2 = b;
      a = gains::Af[0][0]*h1 + gains::Af[0][1]*h2 + gains::Bf[0]*u; b = gains::Af[1][0]*h1 + gains::Af[1][1]*h2 + gains::Bf[1]*u; h1 = a; h2 = b;
    }
  }
};
static void controlLaw(float r, float h1, float h2, float &u) {
  u = gnc::saturatedLqr(gains::Nbar, gains::K[0], gains::K[1], r, h1, h2);
}
int main() {
  CHECK(gnc::freshRangeTarget(true, true, 3.9f, 2.0f, 55.0f), "fresh very-close target is eligible for scan");
  CHECK(!gnc::freshRangeTarget(true, false, 3.9f, 2.0f, 55.0f), "cached close echo cannot refresh scan target");
  CHECK(!gnc::freshRangeTarget(false, true, 30.0f, 2.0f, 55.0f), "stale echo cannot refresh scan target");
  CHECK(gnc::rangeScanBin(35.0f) == 0 && gnc::rangeScanBin(65.0f) == 6 && gnc::rangeScanBin(145.0f) == 22,
        "scan angles map to expected 5-degree sectors");
  CHECK(gnc::rangeScanBin(150.0f) < 0, "angles beyond scan limits are rejected");
  uint32_t full_scan = 0;
  for (unsigned i = 0; i < 23; ++i) full_scan |= (1UL << i);
  const uint32_t localized = (1UL << 10) | (1UL << 11) | (1UL << 12);
  const uint32_t clustered_coverage = (1UL << 10) | (1UL << 11) | (1UL << 12) | (1UL << 13) |
                                      (1UL << 14) | (1UL << 15) | (1UL << 16) | (1UL << 17);
  const uint32_t widespread = (1UL << 0) | (1UL << 4) | (1UL << 8) | (1UL << 12) | (1UL << 16) | (1UL << 20);
  CHECK(!gnc::rangeScanCanLock(clustered_coverage, localized, true), "clustered readings do not prove angular coverage");
  CHECK(!gnc::rangeScanCanLock(full_scan, localized, false), "half/incomplete sweep cannot lock a target");
  CHECK(gnc::rangeScanCanLock(full_scan, localized, true), "complete coverage with localized return can lock");
  CHECK(gnc::broadRangeScan(full_scan, full_scan), "uniform target-range returns are a broad reflection");
  CHECK(gnc::broadRangeScan(full_scan, widespread), "spatially spread hits are broad even below 65 percent");
  CHECK(!gnc::rangeScanCanLock(full_scan, widespread, true), "spread returns cannot lock as a localized target");
  CHECK(gnc::freshConfirmationCount(true, true, 0, 2) == 1, "first distinct hazard sample is pending");
  CHECK(gnc::freshConfirmationCount(false, true, 1, 2) == 0, "cached sample breaks hazard confirmation");
  CHECK(gnc::freshConfirmationCount(true, true, 1, 2) == 2, "second distinct hazard sample confirms");
  for (float tgt : {0.15f, 0.85f, 1.0f, 0.0f}) {                      // step tracking, no overshoot beyond limits
    Loop L; float peak = 0; for (int k = 0; k < 60; k++) { L.tick(tgt, L.x1); peak = fmaxf(peak, fabsf(L.x1 - .5f)); }
    CHECK(fabsf(L.x1 - tgt) < 0.01f, "step to %.2f ended at %.4f", tgt, L.x1);
    CHECK(peak <= fabsf(tgt - .5f) * 1.05f + 1e-3f, "overshoot on step to %.2f", tgt);
  }
  // Deterministic bounded noise: portable on both host and ESP32 toolchains.
  { Loop L; gnc::CUSUMDigitalTwin c(.02f, .06f); bool fa = false;
    for (int k = 0; k < 2000; k++) {
      L.tick(.5f, L.x1);
      const float noise = (k % 2 ? 0.003f : -0.003f);
      fa |= c.update(L.x1 + noise, L.t1 - noise);
    }
    CHECK(!fa, "CUSUM false alarm on healthy loop"); }
  { Loop L; gnc::CUSUMDigitalTwin c(.02f, .06f); int det = -1;  // 14.5 % positive drift is found within 2 samples
    for (int k = 0; k < 100; k++) { L.tick(.5f, L.x1 + .145f); if (c.update(L.x1 + .145f, L.t1) && det < 0) det = k; }
    CHECK(det >= 0 && det <= 2, "CUSUM drift detection index %d", det);
    std::printf("CUSUM detected 14.5%% drift after %d sample(s) = %d ms\n", det + 1, (det + 1) * 50); }
  { Loop L; gnc::CUSUMDigitalTwin c(.02f, .06f); int det = -1;  // negative drift exercises S-
    for (int k = 0; k < 100; k++) { L.tick(.5f, L.x1 - .145f); if (c.update(L.x1 - .145f, L.t1) && det < 0) det = k; }
    CHECK(det >= 0 && det <= 2, "CUSUM negative-drift detection index %d", det); }
  { Loop L; bool ok = true; for (int k = 0; k < 4000; k++) { L.tick((k / 40) % 2 ? .95f : .05f, L.x1 + (k % 2 ? .003f : -.003f)); ok &= std::isfinite(L.x1) && std::isfinite(L.h2); }
    CHECK(ok, "non-finite state during square-wave stress"); }
  { bool ok = true; for (int k = 0; k < 1000; ++k) { float u; controlLaw((k % 20) / 19.f, (k % 101) / 100.f, (k % 31 - 15) / 10.f, u); ok &= std::isfinite(u) && u >= 0.f && u <= 1.f; } CHECK(ok, "shared firmware control law must remain finite and saturated"); }
  std::printf(fails ? "\n%d FAILED\n" : "\nALL HOST CONTROL TESTS PASSED\n", fails); return fails != 0;
}

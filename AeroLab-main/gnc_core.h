#pragma once
#include <cmath>
#include <algorithm>
#include <cstdint>

namespace gnc {

/** A target observation must come from the current sample, not a cached echo. */
inline bool freshRangeTarget(bool echo_fresh, bool new_sample, float distance_cm,
                             float minimum_cm, float maximum_cm) {
    return echo_fresh && new_sample && std::isfinite(distance_cm) &&
           distance_cm >= minimum_cm && distance_cm <= maximum_cm;
}

inline int rangeScanBin(float angle_deg, float minimum_deg = 35.0f,
                        float bin_width_deg = 5.0f, unsigned bin_count = 23) {
    if (!std::isfinite(angle_deg) || bin_width_deg <= 0.0f || bin_count == 0 ||
        angle_deg < minimum_deg || angle_deg > minimum_deg + bin_width_deg * (bin_count - 1)) return -1;
    const int bin = static_cast<int>(std::lround((angle_deg - minimum_deg) / bin_width_deg));
    return bin >= 0 && static_cast<unsigned>(bin) < bin_count ? bin : -1;
}

inline unsigned rangeScanBinCount(uint32_t mask) {
    unsigned count = 0;
    while (mask) { count += mask & 1U; mask >>= 1U; }
    return count;
}

inline float rangeScanMaskSpanDeg(uint32_t mask, float bin_width_deg = 5.0f) {
    if (!mask) return 0.0f;
    unsigned first = 0, last = 0, index = 0;
    bool found = false;
    while (mask) {
        if (mask & 1U) { if (!found) { first = index; found = true; } last = index; }
        mask >>= 1U;
        ++index;
    }
    return static_cast<float>(last - first) * bin_width_deg;
}

/** Broad means target-range returns occupy most samples or a wide angular span. */
inline bool broadRangeScan(uint32_t sample_mask, uint32_t target_mask,
                           float minimum_fraction = 0.65f,
                           float maximum_target_span_deg = 40.0f) {
    target_mask &= sample_mask;
    const unsigned samples = rangeScanBinCount(sample_mask);
    const unsigned hits = rangeScanBinCount(target_mask);
    if (samples >= 8 && static_cast<float>(hits) / static_cast<float>(samples) >= minimum_fraction)
        return true;
    return hits >= 2 && rangeScanMaskSpanDeg(target_mask) > maximum_target_span_deg;
}

/** Require a complete commanded sweep, distributed echo coverage, and a localized return. */
inline bool rangeScanCanLock(uint32_t sample_mask, uint32_t target_mask, bool full_sweep_complete,
                             unsigned minimum_valid_bins = 12,
                             float minimum_coverage_span_deg = 60.0f) {
    target_mask &= sample_mask;
    return full_sweep_complete && rangeScanBinCount(sample_mask) >= minimum_valid_bins &&
           rangeScanMaskSpanDeg(sample_mask) >= minimum_coverage_span_deg && target_mask != 0 &&
           !broadRangeScan(sample_mask, target_mask);
}

/** Consecutive hazard counter advanced only by a new valid sample. */
inline unsigned char freshConfirmationCount(bool new_sample, bool in_hazard,
                                            unsigned char count, unsigned char required) {
    if (!new_sample || !in_hazard) return 0;
    return count < required ? static_cast<unsigned char>(count + 1) : required;
}

/** Apply the firmware's normalized LQR command with actuator limits [0, 1]. */
inline float saturatedLqr(float nbar, float k0, float k1,
                          float reference, float x1_hat, float x2_hat) {
    const float command = nbar * reference - (k0 * x1_hat + k1 * x2_hat);
    return std::max(0.0f, std::min(1.0f, command));
}

/**
 * @brief Embedded Page-Hinkley / CUSUM Sequential Probability Ratio Test
 * Digital Twin Sensor Fault & Drift Detector (Araujo et al., IEEE Access 2025)
 */
class CUSUMDigitalTwin {
public:
    explicit CUSUMDigitalTwin(float k_ref = 0.02f, float h = 0.06f)
        : k_ref_(k_ref), h_(h), s_plus_(0.0f), s_minus_(0.0f), alarm_(false) {}

    bool update(float y_meas, float y_model) {
        float residual = y_meas - y_model;
        s_plus_ = std::max(0.0f, s_plus_ + residual - k_ref_);
        s_minus_ = std::max(0.0f, s_minus_ - residual - k_ref_);
        alarm_ = (s_plus_ >= h_ || s_minus_ >= h_);
        return alarm_;
    }

    void reset() {
        s_plus_ = 0.0f;
        s_minus_ = 0.0f;
        alarm_ = false;
    }

    float Splus() const { return s_plus_; }
    float Sminus() const { return s_minus_; }
    bool alarm() const { return alarm_; }

private:
    float k_ref_;
    float h_;
    float s_plus_;
    float s_minus_;
    bool alarm_;
};

} // namespace gnc

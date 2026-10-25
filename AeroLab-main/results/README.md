# Results index

## MATLAB model figures

The analytics dashboard loads these six generated assets from `results/figures/`:

- `matlab_step_response_comparison.png` — model benchmark; distinguish linear from actuator-saturated response.
- `matlab_bode_plot.png` — model frequency response and calculated margins.
- `matlab_root_locus.png` — pole movement under the plotted assumed model.
- `matlab_digital_twin_residual_araujo2025.png` — software-injected model residual/CUSUM, not a physical sensor residual.
- `matlab_observer_estimation_error.png` — simulated observer convergence.
- `matlab_robustness_envelope.png` — Monte Carlo model variation, not guaranteed hardware robustness.

## Verification

See `verification/verification-record.md` for reproduction commands, passed software checks, and explicit hardware-evidence limits. The scope self-test image and document render reviews are also stored under `verification/`.

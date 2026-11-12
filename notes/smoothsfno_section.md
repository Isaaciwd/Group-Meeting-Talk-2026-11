# Section 1 — Smooth Spectral Weights Make SFNOs Local (and Robust)

*Target: 10–15 min, ~11 slides. Figures referenced from `SmoothSFNO_Paper/figures_sinlat/`.*

---

## Slide 1 — Title / hook  *(~0.5 min)*

**Smoothing the spectral weights of a Spherical Fourier Neural Operator makes it local, and local models generalize.**

- One-line pitch: a tiny penalty on how jagged the SFNO's spectral weights are → much more stable forecasts on flows the model has never seen.
- Testbed: shallow water equations (SWE) on the sphere.

---

## Slide 2 — Motivation: weather is local  *(~1.5 min)*

- Most ML weather models (SFNO, transformers, …) have a **global receptive field** every step.
- Physically, over one short time step a point only "feels" its neighbourhood — the far side of the planet shouldn't matter.
- Lots of parameters + global connections → room for **shortcut learning**: memorizing training-set correlations instead of learning the dynamics.
- Symptom: models look great in-sample, then blow up or ring on out-of-distribution (OOD) inputs.
- Why we care: a changing climate *is* an OOD problem.

---

## Slide 3 — SFNO in one picture  *(~1.5 min)*

- SFNO layer: transform to spherical harmonics → multiply each degree *l* by a learned weight → transform back.
- Key fact: **multiplying in spectral space = convolving in grid space.** Every SFNO layer secretly applies a kernel on the sphere.
- The shape of that kernel is set entirely by how the weights vary with *l*.
- *(cartoon animation: weights moving betweeen jagged and smooth curves vs l on the left, resulting kernel on the sphere on the right.)*

---

## Slide 4 — The idea: jagged in spectral space = ringing in grid space  *(~1.5 min)*

- Same intuition as Gibbs ringing in Fourier series:
  - jagged weights across *l* → kernel with long-range oscillatory side lobes (nonlocal)
  - smooth weights across *l* → kernel energy concentrated near the source (local)
- **Our fix:** add a penalty on the curvature of the weights across degree *l* (a 1-D Laplacian / second difference), with one knob λ.
- Bonus interpretation: neighbouring wavenumbers are neighbouring length scales — the physical response should vary smoothly between them.
- Cheap: no architecture change, no extra inference cost.

---

## Slide 5 — Experimental setup  *(~1.5 min)*

- Two arms, identical except for the penalty:
  - **Control:** λ = 0
  - **Smooth:** λ = 1e-5
- Same small SFNO (4 layers, width 32), **8 random seeds per arm**.
- Deliberately **data-limited** training: 50 random-IC SWE trajectories; 1-step then 2-step autoregressive training. same amount of updates between architectures.
- OOD tests: "vertical split" (one hemisphere raised), Williamson TC6, Gaussian bump, Galewsky jet. **note: only mention tests cases that we actually show in the talk.**

---

## Slide 6 — Cost: slightly worse fit in-sample  *(~1 min)*

**Figure:** `RMSE_vs_epoch.png`

- Smooth arm trains to a somewhat higher loss (~8e-5 vs ~4e-5 final L2).
- Classic bias–variance trade: we give up a little in-sample fit…
- Held-out in-distribution short leads: Control slightly better (2 h: 0.07 vs 0.09 normalized RMSE).
- …but over long rollouts some Control seeds blow up even in-distribution (≥1 seed hits ~1e10 by 50 h); Smooth stays bounded.

---

## Slide 7 — Result 1: kernels become local  *(~1.5 min)*

**Figure:** `kernel_extent_full.png`

- Measure each layer's kernel (its response to a point source) and ask: what fraction of its energy lies within radius *r*?
- **Within 20°: Smooth ≈ 94% vs Control ≈ 24%.**
- Control kernels spread most of their energy across the globe; smooth kernels are compact.
- Consistent across all 8 seeds (thin lines) and insensitive to where the source is placed.

---

## Slide 8 — Result 2: the whole model's sensitivity looks like the solver  *(~1.5 min)*

**Figure:** `2_step_sensitivity.png`

- Kernels are per-layer; what about the full network? Look at the Jacobian: how much does the 2-step output at a point depend on inputs at distance *r*?
- Within 10°: **Smooth 98.8%, true solver 99.0%, Control 83.7%.**
- Control has ~8% of its sensitivity coming from > 20° away — physically spurious long-range influence.
- Takeaway: the smooth model's "region of influence" matches the physics.

---

## Slide 9 — Result 3: OOD generalization (vertical split)  *(~2 min)*

**Figure:** `RMSE_vs_lead_VS.png`

- OOD IC: one half of the sphere raised — nothing like the training data.
- Control: mean normalized RMSE exceeds 1 after ~1 day; median seed ~1e8 by 100 h (blown up).
- Smooth: stays below 0.4 through 50 h; median ~1.2 at 100 h.

**Figure:** `VS_snapshots_median.png` (or `VS_snapshots_control-best_smooth-worst.png`)

- Control develops a large spurious negative-vorticity bias within 8–10 h.
- Smooth tracks the solver's large-scale pattern.
- Strong version: **even the worst Smooth seed beats the best Control seed** over the first 10 h.
- **note: instead of using the figure we already have, it would be great if we can make a gif**

---

## Slide 11 — Takeaways  *(~1 min)*

- SFNO layers are convolutions in disguise; **smooth spectral weights → local kernels**.
- A one-line penalty makes kernels and full-model sensitivities look like the true solver.
- Small in-sample cost, **large gain in stability and OOD skill**.
- Locality is a useful, cheap inductive bias for ML weather/climate models.



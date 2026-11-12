<script setup lang="ts">
/**
 * Cartoon of the spectral-weight / grid-kernel duality for an SFNO layer, in two regimes.
 *
 *  - Jagged regime: every degree l has its own independent random oscillator, so the weight
 *    curve W(l, t) is uncorrelated across neighbouring l at every instant.
 *  - Smooth regime: W(l, t) is a sum of broad Gaussian bumps in l with randomly oscillating
 *    amplitudes, so the curve keeps changing shape but is always smooth in l.
 *
 * Both regimes evolve continuously; the `smooth` prop (driven by a slide click) cross-fades
 * between them. The kernel K(gamma) = sum_l (2l+1)/(4 pi) W_l P_l(cos gamma) (real part only,
 * cartoon) is recomputed every frame, drawn on an orthographic sphere around a point source,
 * and summarised by the fraction of kernel energy within 20 deg. The weights are soft-limited,
 * W -> W_MAX tanh(W / W_MAX), so they always fit the plot without clipping corners.
 * Over 2 minutes of motion: jagged 1-40 % (median 8 %), smooth 95-100 %.
 */
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'

const props = withDefaults(defineProps<{ smooth?: boolean; duration?: number; speed?: number }>(), {
  smooth: false,
  duration: 1600, // regime cross-fade time (ms)
  speed: 1, // time scale of the random motion
})

const L = 48 // max degree
const NG = 721 // gamma table resolution (0..180 deg)
const R_DEG = 20 // radius for the energy readout
const SIZE = 300 // sphere canvas size (px)
const W_LO = -1.6, W_HI = 1.6 // fixed y-range of the weight plot
const SMOOTH_SCALE = 0.65 // smooth-regime amplitude (energy fraction is scale-invariant)
const W_MAX = 1.45 // soft bound on |W| (smooth tanh limiter, stays inside the plot)

// --- random oscillators (seeded so the talk looks the same every time) ------
function mulberry32(seed: number) {
  return () => {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
const rnd = mulberry32(7)
type Osc = { a: number; w: number; p: number }
const osc = (amp: number, wMin: number, wSpan: number): Osc[] =>
  [0, 1].map(() => ({ a: amp * (0.5 + rnd()), w: wMin + wSpan * rnd(), p: 2 * Math.PI * rnd() }))
const evalOsc = (o: Osc[], t: number) => o.reduce((s, q) => s + q.a * Math.sin(q.w * t + q.p), 0)

// jagged: one independent oscillator pair per degree
const jagOsc = Array.from({ length: L + 1 }, () => osc(0.5, 0.4, 1.2))
// smooth: Gaussian bumps in l with oscillating amplitudes (plus a fixed large-scale offset)
const CENTERS = [0, 9, 18, 27, 36], SIG = 6.5
const bumpOsc = CENTERS.map(() => osc(0.6, 0.3, 0.8))
const bump = CENTERS.map((c) => Float64Array.from({ length: L + 1 }, (_, l) => Math.exp(-0.5 * ((l - c) / SIG) ** 2)))

// --- Legendre table P_l(cos gamma_k) -----------------------------------------
const gam = Float64Array.from({ length: NG }, (_, k) => (Math.PI * k) / (NG - 1))
const P: Float64Array[] = []
{
  const x = gam.map(Math.cos)
  P.push(new Float64Array(NG).fill(1))
  P.push(Float64Array.from(x))
  for (let l = 1; l < L; l++) {
    const p = new Float64Array(NG)
    for (let k = 0; k < NG; k++) p[k] = ((2 * l + 1) * x[k] * P[l][k] - l * P[l - 1][k]) / (l + 1)
    P.push(p)
  }
}

// --- per-frame state (plain arrays; only display strings are reactive) -------
const W = new Float64Array(L + 1)
const K = new Float64Array(NG)
let mix = props.smooth ? 1 : 0 // 0 = jagged regime, 1 = smooth regime
let mixFrom = mix, mixTo = mix, mixStart = 0
watch(() => props.smooth, (s) => { mixFrom = mix; mixTo = s ? 1 : 0; mixStart = performance.now() })

const wPath = ref(''), energy = ref(0), isSmooth = ref(mix > 0.5)

function update(now: number) {
  // regime cross-fade
  const u = Math.min(1, (now - mixStart) / props.duration)
  const ease = u < 0.5 ? 2 * u * u : 1 - (-2 * u + 2) ** 2 / 2
  mix = mixFrom + (mixTo - mixFrom) * ease
  isSmooth.value = mix > 0.5

  const t = (now / 1000) * props.speed
  const amps = bumpOsc.map((o, k) => (k === 0 ? 0.4 : 0) + evalOsc(o, t))
  for (let l = 0; l <= L; l++) {
    let s = 0
    for (let k = 0; k < CENTERS.length; k++) s += amps[k] * bump[k][l]
    W[l] = W_MAX * Math.tanh(((1 - mix) * evalOsc(jagOsc[l], t) + mix * SMOOTH_SCALE * s) / W_MAX)
  }
  K.fill(0)
  for (let l = 0; l <= L; l++) {
    const c = ((2 * l + 1) / (4 * Math.PI)) * W[l], p = P[l]
    for (let i = 0; i < NG; i++) K[i] += c * p[i]
  }
  let m = 1e-12, a = 0, b = 0
  const kr = Math.round((R_DEG / 180) * (NG - 1))
  for (let i = 0; i < NG; i++) {
    m = Math.max(m, Math.abs(K[i]))
    const e = K[i] ** 2 * Math.sin(gam[i]); b += e; if (i <= kr) a += e
  }
  energy.value = (100 * a) / b
  drawSphere(m)
  drawPlots()
}

// --- sphere rendering (geometry precomputed once) ----------------------------
const canvas = ref<HTMLCanvasElement | null>(null)
let ctx: CanvasRenderingContext2D | null = null, img: ImageData | null = null
let gIdx: Int32Array, inside: Uint8Array, shade: Float32Array
function precompute() {
  const deg = Math.PI / 180
  const vLat = 25 * deg, sLat = 35 * deg, sLon = -25 * deg
  const src = [Math.cos(sLat) * Math.cos(sLon), Math.cos(sLat) * Math.sin(sLon), Math.sin(sLat)]
  gIdx = new Int32Array(SIZE * SIZE); inside = new Uint8Array(SIZE * SIZE)
  shade = new Float32Array(SIZE * SIZE)
  const r = SIZE / 2 - 2
  for (let j = 0; j < SIZE; j++) for (let i = 0; i < SIZE; i++) {
    const X = (i - SIZE / 2) / r, Y = -(j - SIZE / 2) / r, rr = X * X + Y * Y
    if (rr > 1) continue
    const Z = Math.sqrt(1 - rr) // toward viewer
    // view frame -> earth frame (tilt by the view latitude; view longitude 0)
    const p = [Z * Math.cos(vLat) - Y * Math.sin(vLat), X, Z * Math.sin(vLat) + Y * Math.cos(vLat)]
    const c = Math.max(-1, Math.min(1, p[0] * src[0] + p[1] * src[1] + p[2] * src[2]))
    const g = Math.acos(c) / deg
    const n = j * SIZE + i
    inside[n] = 1
    gIdx[n] = Math.round((g / 180) * (NG - 1))
    shade[n] = 0.75 + 0.25 * Z
  }
}
function drawSphere(m: number) {
  if (!ctx || !img) return
  const d = img.data
  for (let n = 0; n < SIZE * SIZE; n++) {
    if (!inside[n]) continue
    let r: number, g: number, b: number
    {
      // diverging blue-white-red, linear in K / max|K|
      const v = K[gIdx[n]] / m, s = Math.min(1, Math.abs(v))
      if (v >= 0) { r = 247 - 69 * s; g = 247 - 223 * s; b = 247 - 204 * s }
      else { r = 247 - 214 * s; g = 247 - 145 * s; b = 247 - 75 * s }
    }
    const sh = shade[n]
    d[4 * n] = r * sh; d[4 * n + 1] = g * sh; d[4 * n + 2] = b * sh; d[4 * n + 3] = 255
  }
  ctx.putImageData(img, 0, 0)
  ctx.beginPath(); ctx.arc(SIZE / 2, SIZE / 2, SIZE / 2 - 2, 0, 2 * Math.PI)
  ctx.strokeStyle = '#565A5C'; ctx.lineWidth = 1.5; ctx.stroke()
}

// --- SVG line plots ----------------------------------------------------------
const PW = 300, PH = 170, PAD = 30
const xW = (l: number) => PAD + (l / L) * (PW - PAD - 6)
const yW = (w: number) => PH - PAD - ((Math.max(W_LO, Math.min(W_HI, w)) - W_LO) / (W_HI - W_LO)) * (PH - PAD - 8)
const wZeroY = yW(0)
function drawPlots() {
  let d = ''
  for (let l = 0; l <= L; l++) d += `${l ? 'L' : 'M'}${xW(l).toFixed(1)},${yW(W[l]).toFixed(1)} `
  wPath.value = d
}

// --- animation loop ----------------------------------------------------------
let raf = 0
const loop = (now: number) => { update(now); raf = requestAnimationFrame(loop) }
onMounted(() => {
  precompute()
  ctx = canvas.value?.getContext('2d') ?? null
  img = ctx ? ctx.createImageData(SIZE, SIZE) : null
  raf = requestAnimationFrame(loop)
})
onBeforeUnmount(() => cancelAnimationFrame(raf))
</script>

<template>
  <div class="skd">
    <div class="panel">
      <div class="ptitle">Spectral weights</div>
      <svg :width="PW" :height="PH">
        <line :x1="PAD" :x2="PW - 6" :y1="wZeroY" :y2="wZeroY" stroke="#A2A4A3" stroke-dasharray="3,3" />
        <line :x1="PAD" :x2="PAD" y1="6" :y2="PH - PAD" stroke="#000" />
        <line :x1="PAD" :x2="PW - 6" :y1="PH - PAD" :y2="PH - PAD" stroke="#000" />
        <path :d="wPath" fill="none" :stroke="isSmooth ? '#8D7334' : '#565A5C'" stroke-width="2.2" />
        <text :x="PAD - 6" y="14" text-anchor="end" class="ax">W(l)</text>
        <text :x="(PW + PAD) / 2" :y="PH - 8" text-anchor="middle" class="ax">degree l (large scale → small scale)</text>
      </svg>
      <div class="tag" :class="{ good: isSmooth }">{{ isSmooth ? 'smooth regime' : 'jagged regime' }}</div>
    </div>

    <div class="arrow">→</div>

    <div class="panel">
      <div class="ptitle">Kernel on the sphere</div>
      <canvas ref="canvas" :width="SIZE" :height="SIZE" class="sphere" />
      <div class="readout">
        energy within {{ R_DEG }}°: <b class="num">{{ energy.toFixed(0).padStart(3, ' ') }}%</b>
      </div>
    </div>
  </div>
</template>

<style scoped>
.skd { display: flex; align-items: center; justify-content: center; gap: 1.5rem; margin-top: 0.4rem; }
.panel { display: flex; flex-direction: column; align-items: center; }
.ptitle { font-weight: 600; font-size: 0.85rem; margin-bottom: 0.2rem; }
.sphere { width: 220px; height: 220px; }
.arrow { font-size: 2rem; color: #CFB87C; }
.ax { font-size: 10px; fill: #565A5C; }
.tag { font-size: 0.8rem; padding: 0 0.5rem; border-radius: 4px; background: #eee; color: #565A5C; }
.tag.good { background: #F3F0E9; color: #8D7334; font-weight: 600; }
.readout { font-size: 0.85rem; margin-top: 0.3rem; }
.num { font-variant-numeric: tabular-nums; }
</style>

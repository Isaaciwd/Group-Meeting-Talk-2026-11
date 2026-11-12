<script setup lang="ts">
/**
 * Cartoon of a 3 x 3 convolution kernel sliding over a weather-like field, in three stages
 * (driven by slide clicks through the `stage` prop):
 *
 *  0  standard convolution: 9 taps on the grid, the same 9 weights everywhere;
 *  1  dynamic weights: a small generator reads the local field and recomputes the 9 weights at
 *     every location (here: a smoother in flat regions, a derivative across the front);
 *  2  + deformable offsets: the generator also moves each tap off the grid (here: shifted
 *     upstream along the flow and stretched along the front); values between grid points are
 *     read by bilinear interpolation.
 *
 * Synthetic field and hand-made generator rules (cartoon, not a trained model).
 * Tap marker area ~ |weight|, colour = sign (gold +, grey -).
 */
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'

const props = withDefaults(defineProps<{ stage?: number; duration?: number; speed?: number }>(), {
  stage: 0,
  duration: 900, // stage cross-fade (ms)
  speed: 1,
})

// --- grid and field ------------------------------------------------------------------------
const NX = 18, NY = 10, C = 23 // cells, cell size (px)
const GW = NX * C, GH = NY * C
const Y0 = 5.0, AMP = 3.2, KX = (2 * Math.PI) / 9, WIDTH = 0.9 // front: y = Y0 + AMP sin(KX x)
const front = (x: number) => Y0 + AMP * Math.sin(KX * x)
const field = (x: number, y: number) =>
  Math.tanh((y - front(x)) / WIDTH) + 0.35 * Math.exp(-((((x - 13.5 + 1.5 * NX) % NX) - NX / 2) ** 2 + (y - 7.5) ** 2) / 2.5)
// unit tangent of the front (flow direction, eastward) and normal (toward larger field)
function frame(x: number) {
  const dy = AMP * KX * Math.cos(KX * x), n = Math.hypot(1, dy)
  return { t: [1 / n, dy / n], nrm: [-dy / n, 1 / n] }
}

const cells = [] as { x: number; y: number; fill: string }[]
for (let j = 0; j < NY; j++) for (let i = 0; i < NX; i++) {
  const v = field(i + 0.5, j + 0.5) // -1 (cold, top) .. +1 (warm, bottom)
  const s = Math.max(-1, Math.min(1, v))
  // muted blue (cold) -> off-white -> sand (warm)
  const lerp = (a: number[], b: number[], u: number) => a.map((q, k) => Math.round(q + (b[k] - q) * u))
  const rgb = s < 0 ? lerp([238, 240, 242], [143, 170, 200], -s) : lerp([238, 240, 242], [214, 190, 140], s)
  cells.push({ x: i * C, y: j * C, fill: `rgb(${rgb.join(',')})` })
}
const frontPath = Array.from({ length: 91 }, (_, k) => {
  const x = (k / 90) * NX
  return `${k ? 'L' : 'M'}${(x * C).toFixed(1)},${(front(x) * C).toFixed(1)}`
}).join(' ')

// --- kernel -------------------------------------------------------------------------------
const D = [-1, 0, 1].flatMap((dy) => [-1, 0, 1].map((dx) => [dx, dy])) // base tap positions (cells)
const MOVE = 320, PAUSE = 480 // ms per step: glide, then dwell on the grid point
// path: eastward along a row, wrapping across the east/west boundary (periodic, as on a globe); after one full
// lap the kernel steps down one row in the middle of the domain. x is unwrapped here and wrapped when drawn.
const MID = Math.floor(NX / 2)
const PATH: number[][] = []
const ROW = NX + 1 // points per row: a full lap, ending back at the start column
for (let j = 1; j <= NY - 2; j++) for (let k = 0; k < ROW; k++) PATH.push([MID + k + 0.5, j + 0.5])
const W_FIXED = [0.05, 0.12, 0.05, 0.12, 0.32, 0.12, 0.05, 0.12, 0.05] // standard conv: a smoother

let dyn = props.stage >= 1 ? 1 : 0, off = props.stage >= 2 ? 1 : 0
let dynFrom = dyn, offFrom = off, t0 = 0
watch(() => props.stage, () => { dynFrom = dyn; offFrom = off; t0 = performance.now() })

const centre = ref([0, 0])
const taps = ref(D.map(() => ({ x: 0, y: 0, bx: 0, by: 0, w: 0 })))
const output = ref(0)

function bilinear(x: number, y: number) { // field at continuous cell coords via the 4 nearest cell centres
  const gx = x - 0.5, gy = y - 0.5, i = Math.floor(gx), j = Math.floor(gy), u = gx - i, v = gy - j
  const f = (a: number, b: number) => field((((a % NX) + NX) % NX) + 0.5, Math.min(NY - 1, Math.max(0, b)) + 0.5)
  return (1 - u) * (1 - v) * f(i, j) + u * (1 - v) * f(i + 1, j) + (1 - u) * v * f(i, j + 1) + u * v * f(i + 1, j + 1)
}

function update(now: number) {
  const u = Math.min(1, (now - t0) / props.duration), e = u < 0.5 ? 2 * u * u : 1 - (-2 * u + 2) ** 2 / 2
  dyn = dynFrom + ((props.stage >= 1 ? 1 : 0) - dynFrom) * e
  off = offFrom + ((props.stage >= 2 ? 1 : 0) - offFrom) * e

  // raster ("snake") scan over the interior grid points: left -> right along a row, down one row,
  // right -> left, ...; glide smoothly between neighbouring points (MOVE ms), then pause (PAUSE ms)
  const tt = Math.max(0, now - tStart) * props.speed, step = Math.floor(tt / (MOVE + PAUSE)) % PATH.length
  const ph = Math.min(1, (tt % (MOVE + PAUSE)) / MOVE), sm = ph * ph * (3 - 2 * ph) // smoothstep
  const [ax, ay] = PATH[step]
  // next point: one cell east; after a full lap, down one row at the same column; after the last row, stay
  // (the scan then restarts at the top)
  const [bx, by] = step === PATH.length - 1 ? PATH[step]
    : (step + 1) % ROW === 0 ? [ax, PATH[step + 1][1]] : [ax + 1, ay]
  const cx = ax + (bx - ax) * sm, cy = ay + (by - ay) * sm
  centre.value = [cx, cy]

  // "generator": reads the local field. Weights blend from a smoother (flat) to a
  // cross-front derivative (near the front); offsets shift upstream and stretch along the front.
  const { t, nrm } = frame(cx)
  const g = Math.exp(-(((cy - front(cx)) / 2.0) ** 2)) // 1 on the front, 0 far away
  const wDyn = D.map(([dx, dy], k) => (1 - g) * W_FIXED[k] + g * 0.55 * (dx * nrm[0] + dy * nrm[1]))
  let y = 0
  taps.value = D.map(([dx, dy], k) => {
    const along = dx * t[0] + dy * t[1]
    const ox = off * (-0.55 * t[0] + 0.6 * along * t[0]) // upstream shift + stretch along the front
    const oy = off * (-0.55 * t[1] + 0.6 * along * t[1])
    const w = (1 - dyn) * W_FIXED[k] + dyn * wDyn[k]
    const x = cx + dx + ox, yy = cy + dy + oy
    y += w * bilinear(x, yy)
    return { x, y: yy, bx: cx + dx, by: cy + dy, w }
  })
  output.value = y
}

let raf = 0, tStart = 0
const loop = (now: number) => { update(now); raf = requestAnimationFrame(loop) }
onMounted(() => { t0 = tStart = performance.now(); raf = requestAnimationFrame(loop) })
onBeforeUnmount(() => cancelAnimationFrame(raf))

const GOLD = '#CFB87C', DARKGOLD = '#8D7334', GREY = '#565A5C'
const tapR = (w: number) => 3 + 13 * Math.sqrt(Math.min(1, Math.abs(w) / 0.6))
const tapFill = (w: number) => (w >= 0 ? GOLD : GREY)
const cellColor = (w: number) => {
  const a = Math.min(1, Math.abs(w) / 0.6)
  return w >= 0 ? `rgba(207,184,124,${0.15 + 0.85 * a})` : `rgba(86,90,92,${0.15 + 0.85 * a})`
}
const label = computed(() => [
  'Standard convolution: the same 9 weights at every location',
  'Dynamic weights: recomputed from the local weather at every location',
  'Deformable + dynamic: each tap also moves off the grid',
][Math.min(2, Math.max(0, props.stage))])
</script>

<template>
  <div class="dcd">
    <div class="panel">
      <svg :width="GW" :height="GH" class="field">
        <rect v-for="(c, k) in cells" :key="k" :x="c.x" :y="c.y" :width="C" :height="C" :fill="c.fill" />
        <g stroke="#ffffff" stroke-width="0.8" opacity="0.7">
          <line v-for="i in NX - 1" :key="'v' + i" :x1="i * C" :x2="i * C" y1="0" :y2="GH" />
          <line v-for="j in NY - 1" :key="'h' + j" :y1="j * C" :y2="j * C" x1="0" :x2="GW" />
        </g>
        <path :d="frontPath" fill="none" :stroke="DARKGOLD" stroke-width="1.5" stroke-dasharray="5,4" />
        <g v-for="sh in [-1, 0, 1]" :key="'w' + sh" :transform="`translate(${(sh - Math.floor(centre[0] / NX)) * GW},0)`">
        <!-- base grid positions and offset arrows -->
        <g v-for="(p, k) in taps" :key="'t' + k">
          <circle :cx="p.bx * C" :cy="p.by * C" r="2.2" fill="#000" opacity="0.35" />
          <line :x1="p.bx * C" :y1="p.by * C" :x2="p.x * C" :y2="p.y * C" stroke="#000" stroke-width="1.2" opacity="0.55" />
        </g>
        <g v-for="(p, k) in taps" :key="'c' + k">
          <circle :cx="p.x * C" :cy="p.y * C" :r="tapR(p.w)" :fill="tapFill(p.w)" stroke="#000" stroke-width="1" opacity="0.92" />
        </g>
        <rect :x="(centre[0] - 0.5) * C" :y="(centre[1] - 0.5) * C" :width="C" :height="C" fill="none" stroke="#000" stroke-width="2.2" />
        </g>
      </svg>
      <div class="legend">
        <span><i class="dot gold" /> + weight</span><span><i class="dot grey" /> − weight</span>
        <span>size = |weight|</span><span><i class="sq" /> output point</span>
        <span><i class="dash" /> front</span>
      </div>
    </div>

    <div class="side">
      <div class="ptitle">The 9 weights</div>
      <div class="wgrid">
        <div v-for="(p, k) in taps" :key="'w' + k" class="wcell" :style="{ background: cellColor(p.w) }">
          {{ (p.w >= 0 ? '+' : '−') + Math.abs(p.w).toFixed(2) }}
        </div>
      </div>
      <div class="readout">output = Σ weight × value<br>= <b>{{ output.toFixed(2) }}</b></div>
      <div class="stage">{{ label }}</div>
    </div>
  </div>
</template>

<style scoped>
.dcd { display: flex; gap: 22px; align-items: flex-start; justify-content: center; }
.panel { display: flex; flex-direction: column; align-items: center; }
.field { border: 1px solid #A2A4A3; overflow: hidden; }
.legend { display: flex; gap: 14px; font-size: 11px; color: #565A5C; margin-top: 4px; align-items: center; }
.dot { display: inline-block; width: 10px; height: 10px; border-radius: 50%; border: 1px solid #000; vertical-align: -1px; }
.dot.gold { background: #CFB87C; } .dot.grey { background: #565A5C; }
.sq { display: inline-block; width: 10px; height: 10px; border: 2px solid #000; vertical-align: -1px; }
.dash { display: inline-block; width: 18px; border-top: 2px dashed #8D7334; vertical-align: 3px; }
.side { width: 200px; display: flex; flex-direction: column; align-items: center; gap: 8px; }
.ptitle { font-weight: 600; font-size: 14px; }
.wgrid { display: grid; grid-template-columns: repeat(3, 56px); gap: 3px; }
.wcell { height: 40px; display: flex; align-items: center; justify-content: center; font-size: 12px;
  font-variant-numeric: tabular-nums; border: 1px solid #A2A4A3; }
.readout { font-size: 13px; text-align: center; font-variant-numeric: tabular-nums; }
.stage { font-size: 13px; text-align: center; color: #8D7334; font-weight: 600; min-height: 3.2em; }
</style>

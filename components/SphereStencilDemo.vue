<script setup lang="ts">
/**
 * Cartoon of a 3 x 3 stencil on a latitude-longitude grid, seen on the globe (orthographic) and on the
 * grid itself (equirectangular), while its centre glides from the equator toward the pole and back.
 *
 *  - grid stencil: taps one cell apart in grid index (D degrees in latitude and longitude). On the globe its
 *    east-west spacing shrinks as cos(latitude): the stencil collapses toward the pole.
 *  - equal-area stencil (shown from `stage` >= 1): taps one cell apart in physical distance, i.e. the
 *    east-west offset of a tap at latitude phi is D / cos(phi) degrees. On the globe it keeps its size; on
 *    the grid it widens toward the pole.
 *
 * Cell size D = 10 deg for visibility (the model's grid is 1.5 deg; the geometry is the same).
 */
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'

const props = withDefaults(defineProps<{ stage?: number; speed?: number }>(), { stage: 0, speed: 1 })

const D = 10 // cell size (deg)
const LAT_MAX = 65 // turning latitude of the centre
const deg = Math.PI / 180

// --- orthographic globe ---------------------------------------------------------------------
const GS = 240, GR = GS / 2 - 4, PHI0 = 35 * deg // view centre latitude (longitude 0)
function ortho(lat: number, lon: number): [number, number, boolean] {
  const p = lat * deg, l = lon * deg
  const x = Math.cos(p) * Math.sin(l)
  const y = Math.cos(PHI0) * Math.sin(p) - Math.sin(PHI0) * Math.cos(p) * Math.cos(l)
  const vis = Math.sin(PHI0) * Math.sin(p) + Math.cos(PHI0) * Math.cos(p) * Math.cos(l) > 0
  return [GS / 2 + GR * x, GS / 2 - GR * y, vis]
}
function polyline(pts: [number, number, boolean][]) { // split at hidden points
  let d = '', pen = false
  for (const [x, y, v] of pts) {
    if (!v) { pen = false; continue }
    d += `${pen ? 'L' : 'M'}${x.toFixed(1)},${y.toFixed(1)} `
    pen = true
  }
  return d
}
const graticule: string[] = []
for (let lat = -80; lat <= 80; lat += D)
  graticule.push(polyline(Array.from({ length: 181 }, (_, k) => ortho(lat, -180 + 2 * k))))
for (let lon = -180; lon < 180; lon += D)
  graticule.push(polyline(Array.from({ length: 91 }, (_, k) => ortho(-90 + 2 * k, lon))))

// --- equirectangular grid panel -------------------------------------------------------------
const LON0 = -60, LON1 = 60, LATB = -10, LATT = 90, RW = 300, RH = 240
const rx = (lon: number) => ((lon - LON0) / (LON1 - LON0)) * RW
const ry = (lat: number) => ((LATT - lat) / (LATT - LATB)) * RH
const rectV = Array.from({ length: (LON1 - LON0) / D + 1 }, (_, k) => rx(LON0 + k * D))
const rectH = Array.from({ length: (LATT - LATB) / D + 1 }, (_, k) => ry(LATB + k * D))

// --- stencils -------------------------------------------------------------------------------
const OFF = [-1, 0, 1]
function stencil(lat: number, equalArea: boolean): number[][][] { // [row][col] -> [lat, lon]
  return OFF.map((r) => {
    const la = lat - r * D // row -1 = north
    const dl = equalArea ? D / Math.max(Math.cos(Math.min(89, Math.abs(la)) * deg), 0.05) : D
    return OFF.map((c) => [la, c * dl])
  })
}
const lat = ref(0)
let raf = 0, t0 = 0
const MOVE = 4200, HOLD = 1300 // ms: glide equator -> LAT_MAX, hold; and back
function update(now: number) {
  const T = 2 * (MOVE + HOLD), t = (Math.max(0, now - t0) * props.speed) % T
  const leg = t < MOVE + HOLD ? t : t - (MOVE + HOLD), u = Math.min(1, leg / MOVE)
  const s = u * u * (3 - 2 * u)
  lat.value = LAT_MAX * (t < MOVE + HOLD ? s : 1 - s)
}
const loop = (now: number) => { update(now); raf = requestAnimationFrame(loop) }
onMounted(() => { t0 = performance.now(); raf = requestAnimationFrame(loop) })
onBeforeUnmount(() => cancelAnimationFrame(raf))

const sets = computed(() => {
  const out = [{ key: 'grid', pts: stencil(lat.value, false), color: '#565A5C', faded: props.stage >= 1 }]
  if (props.stage >= 1) out.push({ key: 'eq', pts: stencil(lat.value, true), color: '#B08D2E', faded: false })
  return out
})
function netPaths(pts: number[][][], proj: (la: number, lo: number) => [number, number]) {
  const P = pts.map((row) => row.map(([la, lo]) => proj(la, lo)))
  const lines: string[] = []
  for (let i = 0; i < 3; i++) lines.push(`M${P[i].map((p) => p.map((v) => v.toFixed(1)).join(',')).join(' L')}`)
  for (let j = 0; j < 3; j++) lines.push(`M${[0, 1, 2].map((i) => P[i][j].map((v) => v.toFixed(1)).join(',')).join(' L')}`)
  return { lines, dots: P.flat() }
}
const globeNets = computed(() => sets.value.map((s) => ({ ...s, ...netPaths(s.pts, (la, lo) => { const [x, y] = ortho(la, lo); return [x, y] }) })))
const rectNets = computed(() => sets.value.map((s) => ({ ...s, ...netPaths(s.pts, (la, lo) => [rx(lo), ry(la)]) })))

// east-west tap spacing on the ground at the centre latitude (km)
const KM = 6371 * D * deg
const gridKm = computed(() => KM * Math.cos(lat.value * deg))
</script>

<template>
  <div class="ssd">
    <div class="panel">
      <div class="ptitle">On the globe</div>
      <svg :width="GS" :height="GS">
        <circle :cx="GS / 2" :cy="GS / 2" :r="GR" fill="#EEF0F2" stroke="#565A5C" stroke-width="1.5" />
        <path v-for="(d, k) in graticule" :key="k" :d="d" fill="none" stroke="#A2A4A3" stroke-width="0.7" />
        <g v-for="n in globeNets" :key="n.key" :opacity="n.faded ? 0.45 : 1">
          <path v-for="(d, k) in n.lines" :key="k" :d="d" fill="none" :stroke="n.color" stroke-width="2" />
          <circle v-for="(p, k) in n.dots" :key="'d' + k" :cx="p[0]" :cy="p[1]" :r="k === 4 ? 5 : 3.6" :fill="n.color" stroke="#fff" stroke-width="1" />
        </g>
      </svg>
    </div>

    <div class="panel">
      <div class="ptitle">On the latitude–longitude grid</div>
      <svg :width="RW" :height="RH" class="rect">
        <rect x="0" y="0" :width="RW" :height="RH" fill="#EEF0F2" />
        <line v-for="(x, k) in rectV" :key="'v' + k" :x1="x" :x2="x" y1="0" :y2="RH" stroke="#A2A4A3" stroke-width="0.7" />
        <line v-for="(y, k) in rectH" :key="'h' + k" :y1="y" :y2="y" x1="0" :x2="RW" stroke="#A2A4A3" stroke-width="0.7" />
        <text x="4" :y="ry(0) - 3" class="lbl">equator</text>
        <text x="4" :y="ry(90) + 12" class="lbl">pole</text>
        <g v-for="n in rectNets" :key="n.key" :opacity="n.faded ? 0.45 : 1">
          <path v-for="(d, k) in n.lines" :key="k" :d="d" fill="none" :stroke="n.color" stroke-width="2" />
          <circle v-for="(p, k) in n.dots" :key="'d' + k" :cx="p[0]" :cy="p[1]" :r="k === 4 ? 5 : 3.6" :fill="n.color" stroke="#fff" stroke-width="1" />
        </g>
      </svg>
    </div>

    <div class="side">
      <div class="readout">centre latitude<br><b>{{ lat.toFixed(0) }}°N</b></div>
      <div class="readout">east–west tap spacing on the ground</div>
      <div class="key"><i class="sw grid" /> grid stencil: <b>{{ gridKm.toFixed(0) }} km</b></div>
      <div v-if="stage >= 1" class="key"><i class="sw eq" /> equal-area: <b>{{ KM.toFixed(0) }} km</b></div>
      <div class="note">cartoon grid: {{ D }}° cells</div>
    </div>
  </div>
</template>

<style scoped>
.ssd { display: flex; gap: 18px; align-items: flex-start; justify-content: center; }
.panel { display: flex; flex-direction: column; align-items: center; }
.ptitle { font-weight: 600; font-size: 13px; margin-bottom: 2px; }
.rect { border: 1px solid #A2A4A3; }
.lbl { font-size: 10px; fill: #565A5C; }
.side { width: 170px; display: flex; flex-direction: column; gap: 8px; font-size: 13px; padding-top: 24px; }
.readout { font-variant-numeric: tabular-nums; }
.key { font-variant-numeric: tabular-nums; }
.sw { display: inline-block; width: 16px; height: 4px; vertical-align: 3px; margin-right: 4px; }
.sw.grid { background: #565A5C; } .sw.eq { background: #B08D2E; }
.note { font-size: 11px; color: #565A5C; }
</style>

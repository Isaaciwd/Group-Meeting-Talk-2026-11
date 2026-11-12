<script setup lang="ts">
/**
 * Cartoon of the ragged-attention encoder on a regional lat-lon window with synthetic observations.
 *
 *  stage 0: irregular observations (stations, an aircraft corridor, a satellite swath, an empty ocean) over
 *           the regular latent grid, which they do not sit on.
 *  stage 1: one latent grid point draws a radius and attends to every observation inside it; line opacity
 *           shows a (random, cartoon) attention weight.
 *  stage 2: the radius glides between grid points; the neighbour count changes from hundreds to zero.
 *  stage 3: all grid points at once, coloured by how many observations fall within their radius.
 *
 * All positions are synthetic (seeded RNG); counts are those of the cartoon, not of the real model.
 */
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'

const props = withDefaults(defineProps<{ stage?: number; speed?: number }>(), { stage: 0, speed: 1 })

const W = 560, H = 290, R = 46 // panel size and attention radius (px)
const DX = 35 // latent grid spacing (px)

// deterministic RNG (mulberry32) so the cartoon is identical on every render
function rng(seed: number) {
  return () => {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
const rand = rng(7)
const gauss = () => Math.sqrt(-2 * Math.log(rand() + 1e-12)) * Math.cos(2 * Math.PI * rand())

type Obs = { x: number; y: number; kind: 'stn' | 'air' | 'sat' }
const obs: Obs[] = []
// dense land stations ("Europe", upper right)
for (let i = 0; i < 260; i++) {
  const x = 430 + 55 * gauss(), y = 95 + 45 * gauss()
  if (x > 300 && x < W - 4 && y > 4 && y < H - 4) obs.push({ x, y, kind: 'stn' })
}
// sparse island/coastal stations
for (const [x, y] of [[150, 60], [205, 40], [95, 120], [265, 175]]) obs.push({ x, y, kind: 'stn' })
// aircraft corridor (great-circle-ish arc, left to right)
for (let i = 0; i < 70; i++) {
  const u = rand(), x = 20 + u * 420, y = 70 + 55 * Math.sin(Math.PI * u) * -1 + 6 * gauss() + 40
  obs.push({ x, y, kind: 'air' })
}
// satellite swath: a slanted strip of regularly spaced footprints
for (let a = 0; a < 26; a++)
  for (let b = 0; b < 5; b++) {
    const x = 120 + a * 10 + b * 9, y = H - 8 - a * 9 + b * 4
    if (y > 4 && x < W - 4) obs.push({ x: x + 1.5 * gauss(), y: y + 1.5 * gauss(), kind: 'sat' })
  }
const KIND_COLOR: Record<Obs['kind'], string> = { stn: '#565A5C', air: '#3A6EA5', sat: '#8C4A9E' }

// latent grid
const grid: [number, number][] = []
for (let y = DX / 2; y < H; y += DX) for (let x = DX / 2; x < W; x += DX) grid.push([x, y])
const neighbours = (cx: number, cy: number) =>
  obs.map((o, i) => ({ o, i, d: Math.hypot(o.x - cx, o.y - cy) })).filter((n) => n.d <= R)
const counts = grid.map(([x, y]) => neighbours(x, y).length)
const maxCount = Math.max(...counts)

// path of the moving radius: dense stations -> swath -> corridor -> empty ocean
const nearestGrid = (x: number, y: number) =>
  grid.reduce((best, g) => (Math.hypot(g[0] - x, g[1] - y) < Math.hypot(best[0] - x, best[1] - y) ? g : best))
const stops = [nearestGrid(440, 95), nearestGrid(230, 175), nearestGrid(90, 110), nearestGrid(60, 250)]

// attention weights: random positive logits, softmax over each neighbourhood (cartoon only)
const logit = obs.map(() => 2.2 * rand())
function weights(ns: { i: number }[]) {
  const e = ns.map((n) => Math.exp(logit[n.i]))
  const s = e.reduce((a, b) => a + b, 0) || 1
  return e.map((v) => v / s)
}

const pos = ref<[number, number]>(stops[0])
let raf = 0, t0 = 0
const MOVE = 1100, HOLD = 1500 // ms per leg
function update(now: number) {
  if (props.stage !== 2) { pos.value = stops[0]; return }
  const T = stops.length * (MOVE + HOLD), t = (Math.max(0, now - t0) * props.speed) % T
  const k = Math.floor(t / (MOVE + HOLD)), leg = t - k * (MOVE + HOLD)
  const a = stops[k], b = stops[(k + 1) % stops.length]
  const u = Math.min(1, Math.max(0, (leg - HOLD) / MOVE)), s = u * u * (3 - 2 * u)
  pos.value = [a[0] + (b[0] - a[0]) * s, a[1] + (b[1] - a[1]) * s]
}
const loop = (now: number) => { update(now); raf = requestAnimationFrame(loop) }
onMounted(() => { t0 = performance.now(); raf = requestAnimationFrame(loop) })
onBeforeUnmount(() => cancelAnimationFrame(raf))

const active = computed(() => {
  if (props.stage < 1 || props.stage > 2) return []
  const ns = neighbours(pos.value[0], pos.value[1])
  const w = weights(ns), wmax = Math.max(...w, 1e-9)
  return ns.map((n, k) => ({ ...n, a: 0.15 + 0.85 * (w[k] / wmax) }))
})
const activeSet = computed(() => new Set(active.value.map((n) => n.i)))

// heat colour for stage 3: light grey -> CU gold, log-scaled
function heat(c: number) {
  if (c === 0) return '#FFFFFF'
  const u = Math.log1p(c) / Math.log1p(maxCount)
  const lerp = (a: number, b: number) => Math.round(a + (b - a) * u)
  return `rgb(${lerp(238, 176)},${lerp(232, 141)},${lerp(214, 46)})`
}
</script>

<template>
  <div class="rad">
    <svg :width="W" :height="H" class="map">
      <rect x="0" y="0" :width="W" :height="H" fill="#EEF0F2" />
      <!-- stage 3: grid cells coloured by neighbour count -->
      <g v-if="stage >= 3">
        <rect v-for="(g, k) in grid" :key="'h' + k" :x="g[0] - DX / 2" :y="g[1] - DX / 2" :width="DX" :height="DX"
              :fill="heat(counts[k])" stroke="#D0D2D3" stroke-width="0.5" />
        <text v-for="(g, k) in grid" :key="'t' + k" :x="g[0]" :y="g[1] + 3" class="cnt">{{ counts[k] }}</text>
      </g>
      <!-- latent grid points -->
      <circle v-for="(g, k) in grid" v-show="stage < 3" :key="'g' + k" :cx="g[0]" :cy="g[1]" r="1.8" fill="#A2A4A3" />
      <!-- observations -->
      <circle v-for="(o, k) in obs" v-show="stage < 3" :key="'o' + k" :cx="o.x" :cy="o.y" r="2.1"
              :fill="KIND_COLOR[o.kind]" :opacity="stage >= 1 && !activeSet.has(k) ? 0.25 : 0.9" />
      <!-- attention lines and radius -->
      <g v-if="stage === 1 || stage === 2">
        <line v-for="n in active" :key="'l' + n.i" :x1="pos[0]" :y1="pos[1]" :x2="n.o.x" :y2="n.o.y"
              stroke="#B08D2E" :stroke-opacity="n.a" stroke-width="1.1" />
        <circle :cx="pos[0]" :cy="pos[1]" :r="R" fill="#B08D2E" fill-opacity="0.08" stroke="#B08D2E" stroke-width="2" />
        <circle :cx="pos[0]" :cy="pos[1]" r="5" fill="#B08D2E" stroke="#fff" stroke-width="1.5" />
      </g>
      <text x="16" :y="H - 12" class="lbl">open ocean</text>
      <text :x="W - 92" y="16" class="lbl">dense stations</text>
    </svg>

    <div v-if="stage < 3" class="side">
      <div class="key"><i class="dot" style="background:#565A5C" /> surface stations</div>
      <div class="key"><i class="dot" style="background:#3A6EA5" /> aircraft</div>
      <div class="key"><i class="dot" style="background:#8C4A9E" /> satellite swath</div>
      <div class="key"><i class="dot" style="background:#A2A4A3" /> latent grid point</div>
      <div v-if="stage === 1 || stage === 2" class="readout">observations in radius<br><b>{{ active.length }}</b></div>
      <div class="note">cartoon: synthetic observations</div>
    </div>
    <div v-else class="side msg">
      <div>Every grid point sees a <b>different number</b> of observations (0 – {{ maxCount }}).</div>
      <div>Conventional attention can't handle that.</div>
      <div><b class="gold">Ragged attention</b> is built for exactly this regime.</div>
    </div>
  </div>
</template>

<style scoped>
.rad { display: flex; gap: 18px; align-items: flex-start; justify-content: center; }
.map { border: 1px solid #A2A4A3; }
.lbl { font-size: 10px; fill: #565A5C; font-style: italic; }
.cnt { font-size: 8px; fill: #565A5C; text-anchor: middle; font-variant-numeric: tabular-nums; }
.side { width: 170px; display: flex; flex-direction: column; gap: 7px; font-size: 13px; padding-top: 8px; }
.dot { display: inline-block; width: 9px; height: 9px; border-radius: 50%; margin-right: 5px; vertical-align: -1px; }
.readout { font-variant-numeric: tabular-nums; margin-top: 8px; }
.readout b { font-size: 22px; color: #B08D2E; }
.note { font-size: 11px; color: #565A5C; }
.msg { width: 210px; font-size: 16px; line-height: 1.35; gap: 14px; }
.gold { color: #B08D2E; }
</style>

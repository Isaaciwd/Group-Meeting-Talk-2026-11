<script setup lang="ts">
/**
 * Three ways to attend from latent grid points (rows) to the observations near them, with a small cartoon
 * set of neighbour counts. Gold = useful (grid point, observation) pairs, grey = computed but wasted.
 *
 *  stage 0: full attention (every grid point x every observation).
 *  stage 1: + padded attention (each neighbour list padded to the longest one).
 *  stage 2: + ragged attention (lists packed end to end; only real pairs are computed).
 */
import { computed } from 'vue'

const props = withDefaults(defineProps<{ stage?: number }>(), { stage: 0 })

// cartoon neighbour counts per grid point (same spread as real data: dense land, swaths, empty ocean)
const counts = [38, 4, 210, 0, 95, 12, 160, 3]
const total = counts.reduce((a, b) => a + b, 0)
const nmax = Math.max(...counts)
const rows = counts.length

const PW = 240, RH = 14, GAP = 4 // panel width (px), row height, row gap
const PH = rows * (RH + GAP)
const fullScale = PW / total
const padScale = PW / nmax
const ragW = PW * 0.98 // the packed stream wraps over the same rows
const ragPerRow = Math.ceil(total / rows)

// full attention: for each row, which columns are its own neighbours (contiguous block, for the cartoon)
const offsets = counts.map((_, i) => counts.slice(0, i).reduce((a, b) => a + b, 0))

// ragged: pack all segments into one stream, cut into rows of ragPerRow pairs
const ragSegs = computed(() => {
  const segs: { row: number; x: number; w: number; k: number }[] = []
  let p = 0
  counts.forEach((c, k) => {
    let left = c
    while (left > 0) {
      const row = Math.floor(p / ragPerRow), col = p % ragPerRow
      const take = Math.min(left, ragPerRow - col)
      segs.push({ row, x: (col / ragPerRow) * ragW, w: (take / ragPerRow) * ragW, k })
      p += take; left -= take
    }
  })
  return segs
})
const pct = (useful: number, computed: number) => `${Math.round((100 * useful) / computed)} %`
const panels = computed(() => [
  { key: 'full', title: 'Full attention', show: true, eff: pct(total, rows * total), cost: `${rows} × ${total} pairs` },
  { key: 'pad', title: 'Padded to the longest list', show: props.stage >= 1, eff: pct(total, rows * nmax), cost: `${rows} × ${nmax} pairs` },
  { key: 'rag', title: 'Ragged (packed)', show: props.stage >= 2, eff: '100 %', cost: `${total} pairs` },
])
</script>

<template>
  <div class="apd">
    <div v-for="p in panels" :key="p.key" class="panel" :style="{ visibility: p.show ? 'visible' : 'hidden' }">
      <div class="ptitle">{{ p.title }}</div>
      <svg :width="PW" :height="PH">
        <template v-if="p.key === 'full'">
          <g v-for="(c, i) in counts" :key="i">
            <rect x="0" :y="i * (RH + GAP)" :width="PW" :height="RH" fill="#D0D2D3" />
            <rect :x="offsets[i] * fullScale" :y="i * (RH + GAP)" :width="c * fullScale" :height="RH" fill="#B08D2E" />
          </g>
        </template>
        <template v-else-if="p.key === 'pad'">
          <g v-for="(c, i) in counts" :key="i">
            <rect x="0" :y="i * (RH + GAP)" :width="PW" :height="RH" fill="#D0D2D3" />
            <rect x="0" :y="i * (RH + GAP)" :width="c * padScale" :height="RH" fill="#B08D2E" />
          </g>
        </template>
        <template v-else>
          <rect v-for="(s, j) in ragSegs" :key="j" :x="s.x" :y="s.row * (RH + GAP)" :width="Math.max(s.w - 1, 0.5)" :height="RH"
                :fill="s.k % 2 ? '#B08D2E' : '#CFB87C'" />
        </template>
      </svg>
      <div class="stat">{{ p.cost }}<br>useful work: <b>{{ p.eff }}</b></div>
    </div>
  </div>
  <div class="legend">
    rows = latent grid points (neighbour counts {{ counts.join(', ') }}) ·
    <i class="sw" style="background:#B08D2E" /> real (grid point, observation) pairs ·
    <i class="sw" style="background:#D0D2D3" /> wasted compute
  </div>
</template>

<style scoped>
.apd { display: flex; gap: 22px; justify-content: center; }
.panel { display: flex; flex-direction: column; align-items: center; }
.ptitle { font-weight: 600; font-size: 13px; margin-bottom: 4px; }
.stat { font-size: 12px; text-align: center; margin-top: 4px; font-variant-numeric: tabular-nums; }
.stat b { color: #B08D2E; }
.legend { font-size: 11px; color: #565A5C; text-align: center; margin-top: 6px; }
.sw { display: inline-block; width: 12px; height: 8px; margin: 0 3px 0 6px; vertical-align: -1px; }
</style>

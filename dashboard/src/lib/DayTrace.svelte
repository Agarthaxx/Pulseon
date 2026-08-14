<script lang="ts">
  import type { Lane } from "./types";
  import { duration, sourceLabel, clockLabel } from "./format";

  type Props = {
    lanes: Lane[];
    /** Secondes depuis minuit, ou null si le jour affiché n'est pas aujourd'hui. */
    nowOffset: number | null;
    animate: boolean;
  };

  let { lanes, nowOffset, animate }: Props = $props();

  const MINUTES = 1440;
  const LANE_H = 52;
  const BASELINE = LANE_H - 10;
  const PEAK = 8;
  /** Sous ~2 min un bloc serait invisible : on lui garde une largeur plancher. */
  const MIN_WIDTH = 2;

  let hovered = $state<{ lane: string; label: string; x: number } | null>(null);

  function squareWave(lane: Lane): string {
    const parts: string[] = [`M 0 ${BASELINE}`];
    for (const b of lane.blocks) {
      const x1 = (b.start_offset / 60);
      const x2 = Math.max(x1 + MIN_WIDTH, (b.start_offset + b.duration) / 60);
      parts.push(`L ${x1.toFixed(2)} ${BASELINE}`);
      parts.push(`L ${x1.toFixed(2)} ${PEAK}`);
      parts.push(`L ${x2.toFixed(2)} ${PEAK}`);
      parts.push(`L ${x2.toFixed(2)} ${BASELINE}`);
    }
    parts.push(`L ${MINUTES} ${BASELINE}`);
    return parts.join(" ");
  }

  function fillArea(lane: Lane): string {
    return `${squareWave(lane)} L ${MINUTES} ${LANE_H} L 0 ${LANE_H} Z`;
  }

  const HOURS = [0, 3, 6, 9, 12, 15, 18, 21, 24];
</script>

<div class="trace">
  <div class="ruler" aria-hidden="true">
    {#each HOURS as h}
      <span class="tick" style="left: {(h / 24) * 100}%">{String(h).padStart(2, "0")}</span>
    {/each}
  </div>

  <div class="lanes">
    {#each lanes as lane (lane.source)}
      <div class="lane" data-source={lane.source} class:idle={!lane.connected}>
        <div class="lane-head">
          <span class="lane-name">{sourceLabel(lane.source)}</span>
          <span class="lane-total">{duration(lane.total_seconds)}</span>
        </div>

        <div class="lane-plot">
          {#if !lane.connected}
            <div class="lane-empty">
              <span class="dashed"></span>
              <span class="empty-note">collecteur pas encore branché</span>
            </div>
          {:else if lane.kind === "counter"}
            <!-- La quantité est réelle, le placement dans la journée ne l'est
                 pas : les hachures disent que cette barre ne se lit pas sur
                 l'axe des heures. -->
            <div class="lane-counter">
              <span
                class="hatched"
                style="width: max(2%, {(lane.total_seconds / 86400) * 100}%)"
              ></span>
              <span class="empty-note">heure inconnue — l'API ne donne qu'un total</span>
            </div>
          {:else}
            <svg
              viewBox="0 0 {MINUTES} {LANE_H}"
              preserveAspectRatio="none"
              role="img"
              aria-label="{sourceLabel(lane.source)} : {duration(lane.total_seconds)} d'activité"
            >
              <defs>
                <linearGradient id="grad-{lane.source}" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stop-color="var(--sig)" stop-opacity="0.42" />
                  <stop offset="100%" stop-color="var(--sig)" stop-opacity="0.02" />
                </linearGradient>
                <clipPath id="reveal-{lane.source}">
                  <rect x="0" y="0" height={LANE_H} width={MINUTES} class:revealing={animate}>
                  </rect>
                </clipPath>
              </defs>
              <g clip-path="url(#reveal-{lane.source})">
                <path class="area" d={fillArea(lane)} fill="url(#grad-{lane.source})" />
                <path class="wave" d={squareWave(lane)} />
              </g>
            </svg>

            {#each lane.blocks as b}
              <button
                class="hit"
                style="left: {(b.start_offset / 86400) * 100}%; width: max(3px, {(b.duration /
                  86400) *
                  100}%)"
                onmouseenter={() =>
                  (hovered = {
                    lane: lane.source,
                    label: `${b.entity ?? sourceLabel(lane.source)} · ${clockLabel(
                      b.start_offset,
                    )} · ${duration(b.duration)}`,
                    x: (b.start_offset + b.duration / 2) / 864,
                  })}
                onmouseleave={() => (hovered = null)}
                onfocus={() =>
                  (hovered = {
                    lane: lane.source,
                    label: `${b.entity ?? sourceLabel(lane.source)} · ${clockLabel(
                      b.start_offset,
                    )} · ${duration(b.duration)}`,
                    x: (b.start_offset + b.duration / 2) / 864,
                  })}
                onblur={() => (hovered = null)}
                aria-label="{b.entity ?? sourceLabel(lane.source)}, {clockLabel(
                  b.start_offset,
                )}, {duration(b.duration)}"
              ></button>
            {/each}
          {/if}
        </div>
      </div>
    {/each}

    {#if nowOffset !== null}
      <div class="playhead" style="left: {(nowOffset / 86400) * 100}%">
        <span class="playhead-label">{clockLabel(nowOffset)}</span>
      </div>
    {/if}

    {#if hovered}
      <div
        class="tip"
        style="left: {Math.min(Math.max(hovered.x, 8), 92)}%"
        role="status"
      >
        {hovered.label}
      </div>
    {/if}
  </div>
</div>

<style>
  .trace {
    position: relative;
  }

  .ruler {
    position: relative;
    height: 1.1rem;
    margin-left: var(--head-w);
    border-bottom: 1px solid var(--line);
  }

  .tick {
    position: absolute;
    top: 0;
    transform: translateX(-50%);
    font-family: var(--font-mono);
    font-size: 0.66rem;
    letter-spacing: 0.08em;
    color: var(--text-faint);
  }

  .tick:first-child {
    transform: none;
  }

  .tick:last-child {
    transform: translateX(-100%);
  }

  .lanes {
    position: relative;
  }

  .lane {
    display: grid;
    grid-template-columns: var(--head-w) 1fr;
    align-items: center;
    border-bottom: 1px solid var(--line);
  }

  .lane[data-source="pc"] {
    --sig: var(--sig-pc);
  }
  .lane[data-source="tv"] {
    --sig: var(--sig-tv);
  }
  .lane[data-source="playstation"] {
    --sig: var(--sig-ps);
  }

  .lane.idle {
    --sig: var(--text-faint);
  }

  .lane-head {
    display: flex;
    flex-direction: column;
    gap: 0.1rem;
    padding: 0.75rem 1rem 0.75rem 0;
  }

  .lane-name {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.14em;
    color: var(--text-muted);
  }

  .lane-total {
    font-family: var(--font-mono);
    font-size: 1.05rem;
    font-variant-numeric: tabular-nums;
    color: var(--sig);
  }

  .lane.idle .lane-total {
    color: var(--text-faint);
  }

  .lane-plot {
    position: relative;
    height: 52px;
  }

  .lane-plot svg {
    display: block;
    width: 100%;
    height: 100%;
    overflow: visible;
  }

  .wave {
    fill: none;
    stroke: var(--sig);
    stroke-width: 2;
    stroke-linejoin: round;
    vector-effect: non-scaling-stroke;
  }

  .lane-empty,
  .lane-counter {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    height: 100%;
  }

  .dashed {
    flex: 0 0 auto;
    width: 3.5rem;
    border-top: 1px dashed var(--line-bright);
  }

  .hatched {
    flex: 0 0 auto;
    height: 22px;
    border: 1px solid var(--sig);
    border-radius: 2px;
    background-image: repeating-linear-gradient(
      -45deg,
      color-mix(in srgb, var(--sig) 34%, transparent) 0 2px,
      transparent 2px 6px
    );
  }

  .empty-note {
    font-size: 0.72rem;
    color: var(--text-faint);
    font-style: italic;
  }

  .hit {
    position: absolute;
    top: 0;
    height: 100%;
    padding: 0;
    background: transparent;
    border: 0;
    border-radius: 2px;
    cursor: default;
  }

  .hit:hover,
  .hit:focus-visible {
    background: color-mix(in srgb, var(--sig) 16%, transparent);
    outline: none;
  }

  .hit:focus-visible {
    box-shadow: inset 0 0 0 1px var(--sig);
  }

  .playhead {
    position: absolute;
    top: 0;
    bottom: 0;
    width: 1px;
    margin-left: var(--head-w);
    background: var(--live);
    pointer-events: none;
  }

  .playhead::before {
    content: "";
    position: absolute;
    top: -3px;
    left: -3px;
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--live);
  }

  .playhead-label {
    position: absolute;
    bottom: -1.35rem;
    left: 0;
    transform: translateX(-50%);
    font-family: var(--font-mono);
    font-size: 0.66rem;
    color: var(--live);
    letter-spacing: 0.06em;
    white-space: nowrap;
  }

  .tip {
    position: absolute;
    bottom: -2.6rem;
    transform: translateX(-50%);
    padding: 0.32rem 0.6rem;
    background: var(--surface-raised);
    border: 1px solid var(--line-bright);
    border-radius: 4px;
    font-family: var(--font-mono);
    font-size: 0.72rem;
    color: var(--text);
    white-space: nowrap;
    pointer-events: none;
    z-index: 2;
  }

  /* Le tracé s'encre de gauche à droite au chargement, comme un enregistreur
     graphique qui rattrape la journée. */
  rect.revealing {
    animation: ink 1100ms cubic-bezier(0.22, 0.61, 0.36, 1) both;
    transform-origin: left center;
  }

  @keyframes ink {
    from {
      transform: scaleX(0);
    }
    to {
      transform: scaleX(1);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    rect.revealing {
      animation: none;
    }
  }

  @media (max-width: 640px) {
    .lane {
      grid-template-columns: 1fr;
    }
    .lane-head {
      flex-direction: row;
      align-items: baseline;
      justify-content: space-between;
      padding: 0.6rem 0 0.2rem;
    }
    .ruler,
    .playhead {
      margin-left: 0;
    }
  }
</style>

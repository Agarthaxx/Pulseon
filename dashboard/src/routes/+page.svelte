<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import DayTrace from "$lib/DayTrace.svelte";
  import type { DayView } from "$lib/types";
  import { duration, longDate, isToday, shiftDate, sourceLabel } from "$lib/format";

  function todayISO(): string {
    const n = new Date();
    return `${n.getFullYear()}-${String(n.getMonth() + 1).padStart(2, "0")}-${String(
      n.getDate(),
    ).padStart(2, "0")}`;
  }

  let date = $state(todayISO());
  let view = $state<DayView | null>(null);
  let error = $state<string | null>(null);
  let firstPaint = $state(true);
  let nowOffset = $state(secondsSinceMidnight());

  function secondsSinceMidnight(): number {
    const n = new Date();
    return n.getHours() * 3600 + n.getMinutes() * 60 + n.getSeconds();
  }

  $effect(() => {
    const id = setInterval(() => (nowOffset = secondsSinceMidnight()), 30_000);
    return () => clearInterval(id);
  });

  $effect(() => {
    const requested = date;
    invoke<DayView>("day_view", { date: requested })
      .then((v) => {
        view = v;
        error = null;
      })
      .catch((e) => {
        error = String(e);
        view = null;
      });
  });

  $effect(() => {
    if (view && firstPaint) {
      const id = setTimeout(() => (firstPaint = false), 1400);
      return () => clearTimeout(id);
    }
  });

  const breakdown = $derived(
    (view?.lanes ?? [])
      .flatMap((lane) =>
        lane.top_entities.map((e) => ({ ...e, source: lane.source })),
      )
      .sort((a, b) => b.seconds - a.seconds)
      .slice(0, 8),
  );

  const peak = $derived(breakdown[0]?.seconds ?? 1);
  const activeSources = $derived(
    (view?.lanes ?? []).filter((l) => l.total_seconds > 0).length,
  );
</script>

<main>
  <header>
    <div class="brand">
      <span class="mark" aria-hidden="true"></span>
      <span class="wordmark">Pulseon</span>
    </div>

    <nav class="daynav">
      <button onclick={() => (date = shiftDate(date, -1))} aria-label="Jour précédent">
        ←
      </button>
      <span class="daylabel">
        {isToday(date) ? "aujourd'hui" : longDate(date)}
      </span>
      <button
        onclick={() => (date = shiftDate(date, 1))}
        disabled={isToday(date)}
        aria-label="Jour suivant"
      >
        →
      </button>
    </nav>
  </header>

  {#if error}
    <section class="notice">
      <h2>Aucune donnée à lire</h2>
      <p>{error}</p>
      <p class="hint">
        Lance un collecteur pour commencer à enregistrer&nbsp;:
        <code>collector/.venv/bin/python collector/pc_collector.py</code>
      </p>
    </section>
  {:else if view}
    <section class="hero">
      <div class="readout">
        <span class="readout-value">{duration(view.total_seconds)}</span>
        <span class="readout-label">
          {activeSources} source{activeSources > 1 ? "s" : ""} en activité
        </span>
      </div>

      <DayTrace lanes={view.lanes}
        nowOffset={isToday(date) ? nowOffset : null}
        animate={firstPaint} />
    </section>

    <section class="breakdown">
      <h2>Ce qui a consommé la journée</h2>
      {#if breakdown.length === 0}
        <p class="hint">Rien d'enregistré pour ce jour.</p>
      {:else}
        <ol>
          {#each breakdown as item (item.source + item.entity)}
            <li data-source={item.source}>
              <span class="rank-name">{item.entity}</span>
              <span class="bar" style="--pct: {(item.seconds / peak) * 100}%"></span>
              <span class="rank-time">{duration(item.seconds)}</span>
              <span class="rank-src">{sourceLabel(item.source)}</span>
            </li>
          {/each}
        </ol>
      {/if}
    </section>
  {:else}
    <section class="notice"><p class="hint">Lecture…</p></section>
  {/if}
</main>

<style>
  main {
    max-width: 68rem;
    margin: 0 auto;
    padding: 2.5rem 2rem 4rem;
  }

  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
    padding-bottom: 2.75rem;
  }

  .brand {
    display: flex;
    align-items: center;
    gap: 0.6rem;
  }

  /* Le point pulse au rythme d'un relevé : l'app est un instrument branché. */
  .mark {
    width: 9px;
    height: 9px;
    border-radius: 50%;
    background: var(--live);
    box-shadow: 0 0 0 0 color-mix(in srgb, var(--live) 60%, transparent);
    animation: pulse 2.6s ease-out infinite;
  }

  @keyframes pulse {
    0% {
      box-shadow: 0 0 0 0 color-mix(in srgb, var(--live) 55%, transparent);
    }
    70%,
    100% {
      box-shadow: 0 0 0 9px transparent;
    }
  }

  .wordmark {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 1.02rem;
    letter-spacing: -0.01em;
  }

  .daynav {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .daynav button {
    width: 1.85rem;
    height: 1.85rem;
    display: grid;
    place-items: center;
    background: transparent;
    border: 1px solid var(--line);
    border-radius: 5px;
    color: var(--text-muted);
    cursor: pointer;
    transition: border-color 140ms, color 140ms;
  }

  .daynav button:hover:not(:disabled) {
    border-color: var(--line-bright);
    color: var(--text);
  }

  .daynav button:disabled {
    opacity: 0.32;
    cursor: default;
  }

  .daylabel {
    min-width: 11rem;
    text-align: center;
    font-family: var(--font-mono);
    font-size: 0.76rem;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--text-muted);
  }

  .readout {
    display: flex;
    align-items: baseline;
    gap: 0.85rem;
    padding-bottom: 1.5rem;
  }

  .readout-value {
    font-family: var(--font-display);
    font-size: clamp(2.6rem, 7vw, 3.9rem);
    font-weight: 700;
    letter-spacing: -0.035em;
    line-height: 0.9;
    font-variant-numeric: tabular-nums;
  }

  .readout-label {
    font-family: var(--font-mono);
    font-size: 0.74rem;
    letter-spacing: 0.09em;
    text-transform: uppercase;
    color: var(--text-muted);
  }

  .breakdown {
    padding-top: 4rem;
  }

  .breakdown h2 {
    font-family: var(--font-mono);
    font-size: 0.72rem;
    font-weight: 400;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--text-muted);
    margin: 0 0 1.1rem;
  }

  ol {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
  }

  li {
    display: grid;
    grid-template-columns: 12rem 1fr 4.5rem 6rem;
    align-items: center;
    gap: 1rem;
    padding: 0.6rem 0;
    border-bottom: 1px solid var(--line);
  }

  li[data-source="pc"] {
    --sig: var(--sig-pc);
  }
  li[data-source="tv"] {
    --sig: var(--sig-tv);
  }
  li[data-source="playstation"] {
    --sig: var(--sig-ps);
  }

  .rank-name {
    font-size: 0.92rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .bar {
    height: 3px;
    border-radius: 2px;
    background: linear-gradient(
      to right,
      var(--sig) 0 var(--pct),
      var(--line) var(--pct) 100%
    );
  }

  .rank-time {
    font-family: var(--font-mono);
    font-size: 0.84rem;
    font-variant-numeric: tabular-nums;
    text-align: right;
    color: var(--sig);
  }

  .rank-src {
    font-family: var(--font-mono);
    font-size: 0.68rem;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--text-faint);
    text-align: right;
  }

  .notice {
    padding: 3rem 0;
  }

  .notice h2 {
    font-family: var(--font-display);
    font-size: 1.5rem;
    margin: 0 0 0.5rem;
  }

  .hint {
    color: var(--text-muted);
    font-size: 0.88rem;
  }

  code {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: 4px;
    padding: 0.12rem 0.4rem;
  }

  @media (max-width: 640px) {
    main {
      padding: 1.75rem 1.15rem 3rem;
    }
    header {
      flex-direction: column;
      align-items: flex-start;
      gap: 1rem;
    }
    li {
      grid-template-columns: 1fr 4.5rem;
      row-gap: 0.3rem;
    }
    .bar {
      grid-column: 1 / -1;
      order: 3;
    }
    .rank-src {
      grid-column: 1 / -1;
      text-align: left;
      order: 4;
    }
  }
</style>

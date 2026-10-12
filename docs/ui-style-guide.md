# UI Style Guide

## Page shell / container

The dashboard layout (`ControlKeelWeb.Layouts` `:dashboard`) owns the page chrome — sidebar, header, the scroll container, and the content wrapper that sets `container mx-auto` plus `px-4 pt-6 pb-12 sm:px-8 lg:px-8`. Live pages render only their content into `@inner_content`.

Do **not** re-add any of these on the live page:

- `container mx-auto` or a custom `max-w-*` page-width wrapper
- page-level `px-*` / `py-*` / `pt-*` / `pb-*` padding

Start the page directly with its content (title, cards, sections). The wrapper handles width, centering, and spacing.

Reference: `lib/controlkeel_web/components/layouts/dashboard.html.heex`.

## Prefer core components

Before hand-writing markup, check whether a shared component already covers it — use it instead of duplicating classes inline:

- `ControlKeelWeb.CoreComponents`: `<.button>`, `<.input>`, `<.input_component>`, `<.textarea>`, `<.table>`, `<.flash>`, `<.icon>` (`lib/controlkeel_web/components/core_components.ex`).
- `ControlKeelWeb.Typography`: `<.page_title>`, `<.section_title>`, `<.card_title>`.
- Feature modules: `FindingComponents`, `DeploymentComponents`, `ShipReadiness`, `RecentSessions`, `CommandPill` (`lib/controlkeel_web/components/`).

When an existing component is close but not exact, extend the component (new attr or variant) rather than copy-pasting its markup into a page — one source of truth per pattern. Drop to raw markup only when no component fits, and then follow the token and class rules in this guide so the one-off stays consistent.

### Form inputs

Write new form fields against `<.input_component>` (or `<.textarea>`), not the legacy `<.input>`:

```heex
<.input_component field={@form[:q]} type="text" label="Search" placeholder="Task..." phx-debounce="300" />
<.input_component
  field={@form[:risk_tier]}
  type="select"
  label="Risk tier"
  prompt="All tiers"
  options={Enum.map(@risk_tiers, &{String.capitalize(&1), &1})}
/>
```

- `field` binds id/name/value from the form; `label` renders the shared field header.
- Selects take `prompt` (empty option) and `options` (as in `Phoenix.HTML.Form.options_for_select/2`).

## Page title

Optional. Use only where a page needs an explicit heading — not on detail views, single tables, or self-explanatory pages. One primary heading per page. The title and action button can be accommodated in the dashboard header as needed.

Render with `<.page_title>` (`ControlKeelWeb.Typography`):

```heex
<.page_title
  title="Agent Control Plane"
  subtitle="Live mission state, findings, proof coverage, and ship readiness in one view."
/>
```

- `<h1>`: `text-xl font-semibold tracking-tight sm:text-2xl`. The `sm:text-2xl` bump is intentional — don't drop it or add `text-foreground`.
- Subtitle: one concise sentence, `text-muted-foreground`. Omit when the title suffices; no filler copy.
- Pass `class` to adjust the wrapper spacing (e.g. `class="mb-12"`).

## Heading hierarchy

Max three levels; don't skip. Each level maps to a component in `ControlKeelWeb.Typography` — use the component, don't hand-write the classes.

| Level  | Component          | Classes                                               | Use                         |
| ------ | ------------------ | ----------------------------------------------------- | --------------------------- |
| `<h1>` | `<.page_title>`    | `text-xl font-semibold tracking-tight sm:text-2xl`    | Page title (once, optional) |
| `<h2>` | `<.section_title>` | `text-lg sm:text-xl font-semibold text-foreground/90` | Section                     |
| `<h3>` | `<.card_title>`    | `text-base font-semibold`                             | Card / panel                |

## Cards

Every card uses the same container. Vary only what's inside.

```
rounded-2xl border bg-card p-5 shadow-card
```

- `rounded-2xl` — never `rounded-xl` or `rounded-3xl` for cards.
- `bg-card` — solid card surface, not `bg-card/70` or translucent variants.
- `shadow-card` — the one shadow. It is theme-aware: the `--shadow` token in `assets/css/app.css` is soft in light mode and stronger in dark mode (black shadows vanish on dark surfaces). Do not use `shadow-black/20` or mix `shadow-lg`/`shadow-md`.

### Stat card

Label + value (and optional sub-text). Use a grid of these for top-of-page metrics.

```heex
<article class="rounded-2xl border bg-card p-5 shadow-card">
  <p class="text-sm font-medium text-muted-foreground">Proof bundles</p>
  <p class="mt-2 text-xl font-semibold text-foreground/90">{@count}</p>
  <p class="mt-1 text-xs text-muted-foreground">{@caption}</p>
</article>
```

Rich variant (icon chip + progress bar):

```heex
<article class="rounded-2xl border bg-card p-5 shadow-card">
  <div class="flex items-center justify-between gap-3">
    <p class="text-sm font-medium text-muted-foreground">Catch rate</p>
    <span class="rounded-full bg-primary/10 w-8 h-8 flex items-center justify-center text-primary">
      <.icon name="hero-shield-check" class="size-4" />
    </span>
  </div>
  <p class="mt-2 text-xl font-semibold text-foreground/90">{@value}%</p>
  <div class="mt-4 h-2 overflow-hidden rounded-full bg-muted">
    <div class="h-full rounded-full bg-primary" style={"width: #{@value}%"} />
  </div>
  <p class="mt-3 text-xs text-muted-foreground">{@runs} runs</p>
</article>
```

- Label: `text-sm font-medium text-muted-foreground`.
- Value: `mt-2 text-xl font-semibold text-foreground/90` — the `/90` opacity sits the value just behind full-foreground headings.
- Sub-text: `mt-1`/`mt-3 text-xs text-muted-foreground`.
- Icon chip: `rounded-full bg-{tone}/10 w-8 h-8 flex items-center justify-center text-{tone}` with a `size-4` heroicon.

### Panel / section card

A titled container grouping related content.

```heex
<section class="rounded-2xl border bg-card p-5 shadow-card">
  <.section_title>Delivery funnel</.section_title>
  ...
</section>
```

Header row (title + count badge or "view all" link):

```heex
<div class="flex items-center justify-between gap-3">
  <.section_title>Recent missions</.section_title>
  <a href={~p"/missions"} class="inline-flex items-center gap-2 text-sm font-medium text-muted-foreground transition hover:text-primary">
    View all <.icon name="hero-arrow-up-right" class="size-3" />
  </a>
</div>
```

**No nested cards or borders.** A panel already supplies the bordered surface — don't place another `border` + `rounded-2xl` card inside it. Separate inner rows with `divide-y divide-border`, a single `border-t`, or a soft `bg-muted/[0.03]` fill instead. Nesting borders doubles visual weight and creates a boxed-in look.

### Detail card

A card inside a grid, with an icon + title header. Title uses `<h3>`.

```heex
<article class="rounded-2xl border bg-card p-5 shadow-card">
  <div class="flex items-center gap-2">
    <span class="rounded-full bg-info/10 w-8 h-8 flex items-center justify-center text-info">
      <.icon name="hero-cpu-chip" class="size-4" />
    </span>
    <.card_title>Model-backed features</.card_title>
  </div>
  <ul class="mt-4 space-y-2 text-sm text-muted-foreground list-disc ml-5">
    <li>...</li>
  </ul>
</article>
```

## Color & tokens

Color with theme tokens (`bg-*`, `text-*`, `border-*`). They map to CSS variables in `assets/css/app.css` and flip with light/dark automatically. `dashboard_live.ex` and `missions_live.ex` use tokens exclusively for color — match that.

Two patterns cover almost everything:

**Neutral** — surfaces and text hierarchy:

| Token                   | Use                                |
| ----------------------- | ---------------------------------- |
| `bg-background`         | page background                    |
| `bg-card`               | card / panel surface               |
| `bg-muted`              | inactive track, header fill, hover |
| `text-foreground`       | primary text, emphasized values    |
| `text-muted-foreground` | labels, captions, secondary text   |
| `border-border`         | dividers, card/table borders       |

```heex
<p class="text-sm font-medium text-muted-foreground">Label</p>
<p class="mt-2 text-xl font-semibold text-foreground">{@value}</p>
```

**Tinted accent** — soft fill + solid text of the same tone (`bg-{tone}/10 text-{tone}`); a filled bar uses solid `bg-{tone}`:

```heex
<span class="rounded-full bg-primary/10 w-8 h-8 flex items-center justify-center text-primary">
  <.icon name="hero-shield-check" class="size-4" />
</span>
<div class="h-2 rounded-full bg-muted">
  <div class="h-full rounded-full bg-primary" style={"width: #{@value}%"} />
</div>
```

**Primary is the default accent.** Reach for `primary` first: links/active emphasis use `text-primary` (and `hover:text-primary`), filled progress bars use `bg-primary`, chips/buttons use `bg-primary`. Use the other tones (`info`, `success`, `warning`, `destructive`) only when the meaning maps to them — see Tone tokens below.

**Manual colors only when required.** Avoid literals like `text-[#f2e6c9]`, `bg-[rgba(...)]`, or `bg-[var(--ck-*)]` in markup — they don't track the theme. If a token doesn't fit (e.g. a fixed JSON/monospace color), prefer adding a token to `app.css` over a one-off literal.

## Tone tokens

| Token         | Use                 | Chip / pill                          |
| ------------- | ------------------- | ------------------------------------ |
| `primary`     | default accent      | `bg-primary/10 text-primary`         |
| `info`        | neutral guidance    | `bg-info/10 text-info`               |
| `success`     | positive / low-risk | `bg-success/10 text-success`         |
| `warning`     | caution / medium    | `bg-warning/10 text-warning`         |
| `destructive` | error / high-risk   | `bg-destructive/10 text-destructive` |

Status pill (tone by value):

```heex
<span class={[
  "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
  @risk in ["critical", "high"] && "bg-destructive/10 text-destructive ring-destructive/20",
  @risk in ["medium", "moderate"] && "bg-warning/10 text-warning ring-warning/20",
  @risk == "low" && "bg-success/10 text-success ring-success/20"
]}>
  {@risk}
</span>
```

## Tables

```heex
<div class="bg-card border rounded-2xl shadow-card overflow-clip">
  <table class="min-w-full divide-y divide-border text-left text-sm">
    <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground sticky top-0 z-10">
      <tr>
        <th class="px-5 py-3 font-semibold">Mission</th>
        <th class="px-5 py-3 font-semibold w-px whitespace-nowrap"></th>
      </tr>
    </thead>
    <tbody class="divide-y divide-border">
      <tr class="transition hover:bg-muted/30">
        <td class="px-5 py-4">...</td>
        <td class="px-5 py-4 text-right whitespace-nowrap w-px">...</td>
      </tr>
    </tbody>
  </table>
</div>
```

Wrapping the table corners clip and using a sticky header is optional, and depends on the use case.

- `divide-y divide-border` on both `<table>` (header/body separator) and `<tbody>` (row separators).
- `thead`: `bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground`. Add `sticky top-0 z-10` to pin it to the page scroll.
- Cells: `px-5 py-3` (header) / `px-5 py-4` (body).
- Rows: `transition hover:bg-muted/30`.

Container overflow — pick by need:

| Class                        | When                                                            |
| ---------------------------- | --------------------------------------------------------------- |
| `overflow-clip`              | default; keeps rounded corners, lets sticky bind to page scroll |
| `overflow-hidden`            | no sticky header needed                                         |
| `max-h-[SIZE] overflow-auto` | body scrolls inside a fixed box; sticky then binds to that box  |

Narrow action column (icon button / "inspect"):

```heex
<th class="px-5 py-3 font-semibold w-px whitespace-nowrap"></th>
<td class="px-5 py-4 text-right whitespace-nowrap w-px"> ... </td>
```

`w-px whitespace-nowrap` shrinks the column to its content; the other columns take the freed space.

Empty state (single full-width row):

```heex
<tr>
  <td colspan={cols} class="px-5 py-12 text-center">
    <p class="text-base font-medium text-foreground">No missions yet.</p>
    <p class="mt-1 text-sm text-muted-foreground">Start a mission to populate telemetry.</p>
  </td>
</tr>
```

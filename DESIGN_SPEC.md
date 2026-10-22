# Active Agent Product Design Specification

This document defines the visual design system for Active Agent across all surfaces:
the landing page, backend dashboard, Stripe checkout flow, and any future product pages.

All implementations should reference this spec to ensure visual consistency.

The dashboard's React components live in the `actionagent` gem — the dashboard
engine this app mounts — at `actionagent/frontend/` in the gem repo
(github.com/activeagents/activeagent), not in this one. This app's own
JavaScript — landing page, plans, subscriptions, admin — is under
`app/javascript/` here.

---

## Brand Identity

| Property         | Value                          |
|-----------------|-------------------------------|
| Product Name    | **Active Agent** (two words)  |
| Domain          | activeagent.pro               |
| Logo/Mascot     | Red pentagon face, black hat, sunglasses (see `public/images/activeagent-hero.svg`) |
| Tagline         | "Give your Rails app an agent" |

### Naming Conventions
- **Active Agent** - Product brand name (always two words, both capitalized)
- **ActiveAgent** - Ruby gem / code references (e.g., `class TranslationAgent < ApplicationAgent`)
- **activeagent.pro** - Domain / URL reference
- **Active Agents** - AVOID in UI copy (use "Active Agent" singular)

---

## Color System

### Brand Colors (Primary)

| Token                  | Value (Hex) | Usage                                      |
|-----------------------|-------------|---------------------------------------------|
| `--color-accent`      | `#FA343B`   | Primary brand red - CTAs, highlights, active states |
| `--color-accent-hover` | `#E02D33`  | Hover state for primary actions              |
| `--color-accent-b`    | `#FA343B29` | Background tint (16% opacity)               |
| `--color-on-accent`   | `#FFFFFF`   | Text on accent backgrounds                  |

### Theme Variables (Lander CSS)

```css
--theme-hue: 358;           /* Active Agent red/coral */
--theme-saturation: 0.15;   /* Subtle warm tint in backgrounds */
--theme-contrast: 0.85;     /* High readability */
```

### Tailwind Mapping (Dashboard)

The dashboard uses Tailwind CSS. Map the brand accent to `red-` utilities:

| Purpose          | Tailwind Class          | Hex Equivalent |
|-----------------|------------------------|----------------|
| Primary button  | `bg-red-500`           | ~#EF4444       |
| Button hover    | `hover:bg-red-600`     | ~#DC2626       |
| Active nav item | `bg-red-50 text-red-600` | Light tint + text |
| Badges/chips    | `bg-red-100 text-red-700` | Muted tint  |
| Focus rings     | `focus:ring-red-500`   | Ring accent    |
| Accent slider   | `accent-red-500`       | Range input    |

**NEVER USE**: `rose-*`, `indigo-*`, or `blue-*` for brand accent.
These are reserved for specific semantic uses only (blue for info alerts, etc.).

### Semantic Colors

| Purpose     | Light Mode                | Dark Mode                 |
|------------|--------------------------|--------------------------|
| Background | `#f9fafb` / `white`     | `#0f0f0f`                |
| Surface    | `#ffffff`               | `#1a1a1a`                |
| Card       | `#ffffff`               | `rgba(255,255,255,0.05)` |
| Border     | `#e5e7eb`               | `rgba(255,255,255,0.1)`  |
| Border Light | `#f3f4f6`             | `rgba(255,255,255,0.05)` |
| Text Primary | `#111827`              | `#ffffff`                |
| Text Secondary | `#6b7280`            | `rgba(255,255,255,0.6)`  |
| Text Muted | `#9ca3af`               | `rgba(255,255,255,0.4)`  |
| Text Cell  | `#4b5563`               | `rgba(255,255,255,0.7)`  |
| Success    | `#16a34a`               | Same                     |
| Warning    | `#eab308`               | Same                     |
| Error      | `#dc2626` (distinct from accent) | Same            |
| Info       | `#3b82f6`               | Same                     |

### Semantic Tint Pairs

Every semantic color has a **soft** fill and a **text** shade. Use the pair
together for badges, value pills and inline alerts; never a solid semantic
fill behind text.

| Pair      | Light soft / text       | Dark soft / text                        |
|-----------|-------------------------|-----------------------------------------|
| Success   | `#dcfce7` / `#166534`   | `rgba(22,163,74,0.15)` / `#4ade80`      |
| Warning   | `#fef9c3` / `#854d0e`   | `rgba(234,179,8,0.15)` / `#facc15`      |
| Error     | `#fee2e2` / `#991b1b`   | `rgba(220,38,38,0.15)` / `#f87171`      |
| Info      | `#dbeafe` / `#1e40af`   | `rgba(59,130,246,0.15)` / `#93c5fd`     |

Tokens: `--color-{success,warning,error,info}-soft` and `-text` in
`actionagent/frontend/tokens.css` (mirrored by `ActiveAgent::Evals::DesignTokens`).

**Note**: For dark mode, do NOT use Tailwind's `gray-900`/`gray-950` - they have a blue tint. Use the hex values above.

---

## Typography

### Font Stack

| Purpose    | Family                                    | CSS Variable    |
|-----------|-------------------------------------------|-----------------|
| Body      | Inter Variable, Arial, sans-serif          | `--font-text`   |
| Code      | JetBrains Mono, Courier New, monospace     | `--font-mono`   |

### Scale

| Token    | Size    | Usage                    |
|---------|---------|--------------------------|
| `xs`    | 13.75px | Captions, badges         |
| `s`     | 13.75px | Body small, feature items |
| `m`     | 16.5px  | Body default             |
| `l`     | 22px    | Subheadings, prices      |
| `xl`    | 44px    | Section headings         |
| `xxl`   | 66px    | Hero heading             |

---

## Mascot / Avatar

The Active Agent mascot is used consistently across:
- Landing page hero (`activeagent-hero.svg`)
- Dashboard sidebar logo
- Agent builder preview
- Error/empty states

Agent cards intentionally omit the mascot — repeating the same mark on every
card adds noise without information; the space goes to the scorecard metrics.

### SVG Source
- Primary: `public/images/activeagent-hero.svg` (500x500 viewBox)
- React component: `frontend/components/AgentAvatar.jsx` (dashboard engine)
- Key colors: Face `#EB5555`, Hat/Frames `#000000`, Lenses `#000000` at 92% opacity

### Usage Rules
1. Always use the **same mascot design** everywhere - no variant body shapes
2. Decorations (instructions/tools) are shown as emoji badges above/below the mascot
3. Size ranges: 28px (sidebar logo) to 200px (hero/builder preview)
4. The mascot SVG should respect dark mode via the `.lens-fill` CSS class when used in HTML contexts

---

## Agent Builder UX

The agent builder follows the same interaction pattern on both the lander and dashboard:

### Layout Pattern
```
  [Instruction emojis above]
       [Mascot SVG]
   [Tool emojis below]
```

### Presets (Shared between lander & dashboard)
| Preset         | Instructions           | Tools                    |
|---------------|------------------------|--------------------------|
| Claude Code   | GitHub                 | Terminal, Code           |
| Web Scraper   | TypeScript             | Playwright, Fetch        |
| Data Analyst  | Python                 | Database, Search, Code   |
| DevOps        | GitHub, AWS            | Terminal, Slack, Code    |
| Polyglot      | Ruby, Python, TypeScript | Translate, Code        |
| Research      | GitHub                 | Fetch, Search, Memory    |

### Instructions (System/Developer Messages)
GitHub, Ruby, Rails, AWS, GCP, Python, TypeScript, Docker, Kubernetes

### Tools (MCPs & Integrations)
Terminal, Playwright, Filesystem, Code, Database, Slack, Fetch, Search, Edit, Translate, Memory

### Chip/Badge Interaction
- **Selected**: `bg-red-500 text-white` (solid accent)
- **Unselected**: `bg-gray-100 text-gray-700` (neutral)
- **Shape**: Rounded pill (`rounded-full`)

---

## Pricing Structure

### The Gems (Open-Source & Extensions)

| Tier                    | Price          | License     | CTA           |
|------------------------|----------------|-------------|---------------|
| ActiveAgent.dev         | Free           | MIT         | Get Started   |
| ActiveAgent.PRO         | $99/mo or $995/yr | Commercial | Subscribe to Pro |
| activeagent-enterprise  | $269+/mo per 100 agents | Commercial | Contact Sales |

### The Platform (Hosted Observability)

| Tier                | Price              | Target              |
|--------------------|--------------------|---------------------|
| Self-Hosted        | Free               | Developers          |
| Pro Platform       | $99/mo or $500/yr  | Small/medium teams  |
| Enterprise Platform| $2,000+/yr         | Enterprise          |

### Stripe Checkout
- Use `$99.00` for Pro plan checkout display (matching the lander pricing)
- Annual pricing shows per-year amount
- Trial days shown when applicable
- "Most Popular" badge on Pro plan card

### Card Highlighting
- Featured/Pro plan card: `border-red-500 shadow-xl` with `bg-red-500` badge
- Free plan: `border-gray-200` with tertiary CTA button
- Enterprise: `border-gray-200` with tertiary CTA button

---

## Component Patterns

### Styling Approach for Theme Support

For components that need theme support, use **inline styles with a colors object** rather than Tailwind classes for background, text, and border colors. This ensures consistency between themes.

```jsx
const colors = {
  cardBg: darkMode ? 'rgba(255,255,255,0.05)' : '#ffffff',
  border: darkMode ? 'rgba(255,255,255,0.1)' : '#e5e7eb',
  textPrimary: darkMode ? '#ffffff' : '#111827',
};

// Use inline styles for theme-dependent colors
<div style={{
  background: colors.cardBg,
  border: `1px solid ${colors.border}`,
  borderRadius: '12px',  // Layout values stay constant
  padding: '20px'        // Layout values stay constant
}}>
```

Use Tailwind for **layout-only** properties that don't change between themes:
- `flex`, `grid`, `items-center`, `justify-between`
- `space-x-4`, `gap-4`
- `rounded-lg`, `rounded-xl`
- `animate-spin`, `transition-colors`

### Buttons

| Style     | Lander Class        | Dashboard Tailwind                    |
|----------|--------------------|-----------------------------------------|
| Primary  | `button primary`   | `bg-red-500 text-white hover:bg-red-600 rounded-lg` |
| Secondary | `button secondary` | `border border-gray-300 text-gray-700 hover:bg-gray-50 rounded-lg` |
| Tertiary | `button tertiary`  | `bg-gray-100 text-gray-700 hover:bg-gray-200 rounded-lg` |
| Disabled | -                  | `bg-gray-200 text-gray-400 cursor-not-allowed` |

### Cards

| Context        | Lander                  | Dashboard (use inline styles for dark mode support) |
|---------------|------------------------|-----------------------------------------------------|
| Feature card  | `.feature-card`        | `background: colors.cardBg, border: colors.border, borderRadius: '12px'` |
| Highlighted   | `.feature-card.highlighted` | `border-red-500 shadow-xl`          |
| Agent card    | -                      | Same card pattern with hover state via `onMouseEnter/Leave` |

### Status Badges

Soft tint + strong text from the semantic tint pairs above. Pill shape
(`rounded-full`) for states and values, 4px radius for mono identifiers.

| State      | Tokens                                        | Legacy Tailwind                 |
|-----------|-----------------------------------------------|---------------------------------|
| Active    | `--color-success-soft` / `--color-success-text` | `bg-green-100 text-green-800` |
| Trial     | `--color-info-soft` / `--color-info-text`       | `bg-blue-100 text-blue-800`   |
| Warning   | `--color-warning-soft` / `--color-warning-text` | `bg-yellow-100 text-yellow-800` |
| Error     | `--color-error-soft` / `--color-error-text`     | `bg-red-100 text-red-800`     |
| Inactive  | `--color-muted` / `--color-text-cell`           | `bg-gray-100 text-gray-500`   |

Prefer the tokens; the Tailwind column is for reading older components, and
it has no dark-mode counterpart.

### Focus States
- Input focus: `focus:ring-2 focus:ring-red-500 focus:border-transparent`
- Button focus: Same ring treatment
- Link focus: Underline + color shift

---

## Ranked Data & Comparison Tables

Use this pattern whenever rows are **compared against each other**: model
benchmarks, agent leaderboards, evaluation run comparisons, provider cost
tables, plan matrices. It is the richer sibling of the dense `DataTable`
(which stays the default for operational lists such as traces, runs and
interactions, where rows are scanned, not ranked).

Reference: the model table at rubyonrails.org/ai. The qualities to keep are
clean row separation, sortable two-line headers, and a value pill in every
numeric cell whose tint says at a glance whether that value is good, middling
or poor relative to the other rows.

```
MODEL                       ACCURACY      SPEED ▲       TOKENS        COST
                            TASK SCORE    TASK TIME     PER RUN       PER RUN
──────────────────────────────────────────────────────────────────────────────
(◎) Claude Opus 5.5  xhigh  ( 65.3% )    ( 53m 31s )  ( 27,159,917 ) ( $10.53 )
(◎) GPT-6 Astra      xhigh  ( 62.3% )    ( 22m 36s )  (  1,978,796 ) (  $4.71 )
──────────────────────────────────────────────────────────────────────────────
```

### Anatomy

| Part | Spec |
|------|------|
| Identity cell | 24px provider/agent mark, name in `--font-text` 15px/600, then a variant chip (`xhigh`, `medium`, `v3`) in 13px `--color-text-secondary`, regular weight, 8px gap. The mark is a logo or glyph, never the mascot. |
| Metric header | Two lines. Line 1: metric name, 11px mono uppercase, `letter-spacing: 0.05em`, `--color-text-primary`, weight 700. Line 2: unit or qualifier ("TASK SCORE", "PER RUN"), same size, `--color-text-secondary`, weight 500. |
| Value pill | Full pill (`border-radius: 9999px`), `padding: 10px 16px` (compact tables: `6px 12px`), text centered, `--font-mono` 15px/700, `font-variant-numeric: tabular-nums`. Tinted by rank (below). Fills its column width on mobile; `min-width: 7ch` on desktop. |
| Row | `padding-block: 16px`, hairline bottom border `--color-border` only. No zebra striping, no vertical rules, no outer card border on the table itself. Hover: `--color-hover` background. |
| Sort indicator | A small solid caret after the active column's line-1 label: `▲` ascending, `▼` descending, 9px, `--color-accent-ui`. Only the active column shows a caret. |

### Rank tints

Pills reuse the existing semantic soft/text token pairs. No new colors.

| Rank band | Background | Text | Meaning |
|-----------|------------|------|---------|
| Good | `--color-success-soft` | `--color-success-text` | Top third of the column |
| Middle | `--color-warning-soft` | `--color-warning-text` | Middle third |
| Poor | `--color-error-soft` | `--color-error-text` | Bottom third |
| Unranked | `--color-muted` | `--color-text-cell` | Missing value, n/a, single row |

Rules:
1. **Rank within the column, per table.** Each column declares its direction
   (`higher` is better for accuracy; `lower` is better for time, tokens, cost)
   and rows are banded into terciles by that direction. A value's tint can
   change when rows are added or filtered; that is correct, the tint is
   relative.
2. **Terciles by default, thresholds when the domain has them.** Eval scores
   keep the fixed thresholds from the Evaluations view (≥ 0.85 good,
   0.70–0.84 middle, < 0.70 poor). Cost, latency and token counts have no
   absolute "good", so they band by tercile.
3. **Never tint the identity cell.** Color lives in the pills only; the row
   stays neutral so a poor row does not read as an error state.
4. **Never rely on color alone.** The pill always carries the formatted
   value, and the cell gets `data-rank="good|mid|poor"` plus a visually
   hidden rank word for screen readers (`<span class="sr-only">best third</span>`).
5. **Dark mode uses the dark soft/text pairs already in `tokens.css`**
   (15% alpha fills, 400-weight tinted text). Do not hand-pick darker
   pastels.

### Sorting

- Every metric header is a `<button>` inside the `<th>`; `<th>` carries
  `aria-sort="ascending|descending|none"`.
- First click on a column sorts by that column's **better** direction
  (accuracy descending, cost ascending), second click flips it, so the first
  tap always puts the strongest row on top.
- The identity column sorts alphabetically; it is a valid sort but never the
  default. Default sort is the table's headline metric (accuracy for model
  tables, score for eval comparisons).
- Sort is a pure client-side reorder with no row animation; rows re-render
  in place. Sort state is reflected in the header caret only, not in a
  separate "sorted by" line.
- Persist the chosen column in the URL query (`?sort=cost&dir=asc`) on
  product pages so a sorted view is linkable; on the lander, `localStorage`
  is enough.

### Responsive behaviour

| Width | Layout |
|-------|--------|
| ≥ 900px | Classic table: identity column auto-width, metric columns equal, pills right-aligned in cells with `min-width: 7ch`. |
| 600–899px | Same table; header line 2 hides, pill padding drops to `6px 12px`. |
| < 600px | Each row becomes a card: identity line on top, then the pills in a 4-column grid (`grid-template-columns: repeat(4, 1fr)`) that fills the row width. Headers collapse to one sticky two-line header row above the list, columns aligned with the pill grid. Nothing scrolls horizontally. |

### Marketing vs product

The pattern is the same on both surfaces; only density differs.

| Property | Lander | Dashboard |
|----------|--------|-----------|
| Row padding | 20px | 12px |
| Pill padding | 10px 16px | 6px 12px |
| Name size | 17px | 14px |
| Pill text | 15px | 13px |
| Row divider | `--color-border` | `--color-border-light` |

### Implementation notes

- Dashboard: `components/data/ComparisonTable.prompt.md` and
  `components/data/ValuePill.prompt.md` in the design skill describe the
  React API. Keep the colours in a `colors` object per the theme pattern
  above; the rank band is a data attribute, not a Tailwind class.
- Lander: a static `<table class="comparison">` with the same data
  attributes. Sorting is a 30-line vanilla script, not a library.
- Specimen: `docs/design/comparison-table/specimen.html` renders the pattern
  in both themes with working sort and tercile banding. Open it in a
  browser or run it through the Playwright harness to compare a change.

---

## Spacing & Layout

### Lander
- Section spacing: `--space-section: 60px`
- Card padding: `--space-card-m: 24px`
- Border radius: `--radius-s: 8px`, `--radius-m: 12px`, `--radius-l: 16px`
- Grid: 3-column (`.columns-3`) and 2-column (`.columns-2`) layouts

### Dashboard
- Page padding: `p-6`
- Card padding: `p-6` or `p-8`
- Border radius: `rounded-lg` (8px) or `rounded-xl` (12px)
- Grid: Responsive `grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4`
- Sidebar width: `w-64` (256px)

---

## Dark Mode

The lander supports dark mode via `.theme-dark` class with recalculated OKLCH colors.
The dashboard supports dark mode via `ThemeContext` with a toggle in the Header.

### Dark Mode Color Palette

**CRITICAL**: Do NOT use Tailwind's default gray utilities (`bg-gray-900`, `bg-gray-950`, etc.) for dark backgrounds. These have a blue tint that doesn't match the brand.

Use these neutral dark colors instead:

| Token | Hex Value | Usage |
|-------|-----------|-------|
| `bg-main` | `#0f0f0f` | Main page background |
| `bg-surface` | `#1a1a1a` | Sidebar, header, elevated surfaces |
| `bg-card` | `rgba(255,255,255,0.05)` | Card backgrounds |
| `border` | `#2a2a2a` or `rgba(255,255,255,0.1)` | Borders |
| `bg-hover` | `#252525` | Hover states |
| `text-primary` | `#ffffff` | Primary text |
| `text-secondary` | `rgba(255,255,255,0.6)` | Secondary text, descriptions |
| `text-muted` | `rgba(255,255,255,0.4)` | Muted text, captions |

### Theme Implementation Pattern

**CRITICAL**: Always use a **unified component structure** with a single return statement. Only colors should differ between themes - never duplicate layout, font sizes, padding, or spacing.

#### Correct Pattern (Single Structure)

```jsx
export default function MyComponent() {
  const { darkMode } = useTheme();

  // Define all theme colors in one place
  const colors = {
    bg: darkMode ? 'transparent' : '#f9fafb',
    cardBg: darkMode ? 'rgba(255,255,255,0.05)' : '#ffffff',
    border: darkMode ? 'rgba(255,255,255,0.1)' : '#e5e7eb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
  };

  // Single return with color variables
  return (
    <div style={{ backgroundColor: colors.bg }}>
      <h1 style={{ color: colors.textPrimary }}>Title</h1>
      <p style={{ color: colors.textSecondary }}>Description</p>
    </div>
  );
}
```

#### Incorrect Pattern (AVOID)

```jsx
// DON'T DO THIS - separate implementations cause inconsistencies
if (!darkMode) {
  return (
    <div className="bg-white p-6">  {/* Different padding */}
      <h1 className="text-2xl">Title</h1>  {/* Different size */}
    </div>
  );
}
return (
  <div className="preview-content">  {/* Different structure */}
    <h1 className="text-xl">Title</h1>  {/* Inconsistent */}
  </div>
);
```

### Theme Context

The dashboard uses `ThemeContext` for centralized theme state:

```jsx
import { ThemeProvider, useTheme } from '../contexts/ThemeContext';

// In component:
const { darkMode, toggleDarkMode } = useTheme();
```

- Theme preference is persisted in `localStorage`
- Toggle button is in the Header component
- All dashboard components should use `useTheme()` for theme-aware styling

---

## Icon System

| Context   | System      | Examples                        |
|----------|-------------|---------------------------------|
| Lander   | Font Awesome 6.7.2 | `fa-solid fa-circle-check` |
| Dashboard | Emoji + inline SVG | Emoji for nav, SVG for actions |

Long-term goal: Migrate to a single icon system (SVG preferred) for consistency.

---

## Accessibility

- All interactive elements must have visible focus states
- Color contrast ratio: minimum 4.5:1 for text
- SVG mascot includes `role="img"` and `aria-label`
- Form inputs have associated labels
- Buttons have descriptive text (not icon-only without aria-label)

---

## Observability UX Patterns

The dashboard includes four observability views that align with the product previews shown on the landing page. These views provide comprehensive insight into agent operations.

### Navigation Structure

The sidebar organizes navigation into two sections:

```
Agents
  - Agents (list)
  - New Agent

Observability
  - Traces
  - Metrics
  - Evaluations
  - Interactions
```

### Traces View

**Purpose**: Display every agent call broken into spans with timing and costs.

| Component | Description |
|-----------|-------------|
| Trace Header | Shows trace ID, agent#action, duration, cost, HTTP status |
| Timeline Scale | Horizontal scale from 0ms to total duration |
| Span Rows | Nested rows showing prompt → generate → LLM call → thinking → response |
| Token Breakdown | Displays thinking tokens (🧠), input (↓), output (↑) |

**Span Types & Colors**:
| Type | Icon | Color | Description |
|------|------|-------|-------------|
| Root | → | `bg-gray-400` | Top-level agent action |
| Prompt | ◇ | `bg-blue-400` | Prompt construction |
| Generate | ▶ | `bg-purple-500` | Generation call |
| LLM | ◆ | `bg-red-500` | Provider API call |
| Thinking | 💭 | `bg-amber-400` | Extended thinking/reasoning |
| Tool | 🔧 | `bg-green-500` | Tool execution |
| Response | ◇ | `bg-teal-400` | Response processing |

### Metrics View

**Purpose**: Track requests, latency, costs, and token usage in real-time.

| Component | Description |
|-----------|-------------|
| Metric Cards | 4-column grid showing key stats with sparklines |
| Sparklines | Mini line charts showing trend over time |
| Trend Indicators | Arrow + percentage showing change vs previous period |
| Hourly Chart | Bar chart showing requests per hour |
| Provider Breakdown | Progress bars showing usage by provider |
| Top Agents Table | Ranked list with requests, cost, avg cost/request |

**Metric Card Pattern**:
```
┌─────────────────────────┐
│ Total Requests          │
│ 12.8K                   │
│ ↑ 23% vs last week  ~~~│
└─────────────────────────┘
```

### Evaluations View

**Purpose**: Score agent outputs with LLM-as-judge evaluations.

| Component | Description |
|-----------|-------------|
| Evaluation Card | Expandable card showing eval name, timestamp, avg score |
| Score Bars | Animated progress bars with value labels |
| Score Tooltips | On-hover details with min/max/avg stats |
| Eval Details | Model judge, criteria, samples passed |

**Score Status Colors**:
| Status | Score Range | Color |
|--------|------------|-------|
| High | ≥ 0.85 | `bg-green-500` |
| Medium | 0.70 - 0.84 | `bg-yellow-500` |
| Low | < 0.70 | `bg-red-500` |

### Interactions View

**Purpose**: Display message fragments with caching and deterministic tool calls.

| Component | Description |
|-----------|-------------|
| Session Card | Expandable card showing session ID, fragment count |
| Fragment | Container showing cache status, messages, metadata |
| Message Bubble | Role-colored bubbles for user/assistant/tool |
| Cache Badge | Status indicator (cache hit, deterministic, generated) |

**Fragment Types**:
| Type | Badge Style | Description |
|------|-------------|-------------|
| Message | `bg-gray-100` | Standard message fragment |
| Tool | `bg-blue-100` | Tool call fragment (deterministic) |
| Thinking | `bg-amber-100` | Extended thinking fragment |

**Cache Status Indicators**:
| Status | Icon | Color | Description |
|--------|------|-------|-------------|
| Cache Hit | ⚡ | `text-green-600` | Retrieved from cache |
| Deterministic | 🔒 | `text-blue-600` | Tool call with fixed output |
| Generated | ● | `text-gray-500` | Newly generated |

### Shared Patterns

**Expandable Cards**: All observability views use a consistent expandable card pattern:
- Click header to expand/collapse
- Chevron icon rotates on expand
- Expanded content has `bg-gray-50` background
- Smooth height transition

**Loading States**: All views show centered spinner during data fetch:
```jsx
<div className="animate-spin rounded-full h-8 w-8 border-b-2 border-red-500" />
```

**Empty States**: Centered text with suggestion:
```
No [items] yet
[Instruction on how to create first item]
```

**Filter/Period Controls**: Top-right placement with consistent styling:
- `px-3 py-2 border border-gray-300 rounded-lg text-sm`
- Focus ring: `focus:ring-2 focus:ring-red-500`

**Ranked Lists**: Top Agents, model comparisons and eval run comparisons use
the comparison table pattern (see *Ranked Data & Comparison Tables*): sortable
two-line headers, rank-tinted value pills, hairline rows.

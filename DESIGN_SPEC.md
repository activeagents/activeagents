# Active Agent Product Design Specification

This document defines the visual design system for Active Agent across all surfaces:
the landing page, backend dashboard, Stripe checkout flow, and any future product pages.

All implementations should reference this spec to ensure visual consistency.

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
| Background | `white` / `gray-50`     | oklch calculated          |
| Surface    | `gray-50` / `gray-100`  | oklch calculated          |
| Text Primary | `gray-900`             | oklch calculated          |
| Text Secondary | `gray-500` / `gray-600` | oklch calculated       |
| Success    | `green-500` / `green-600` | Same                    |
| Warning    | `yellow-500`            | Same                      |
| Error      | `red-700` (distinct from accent) | Same             |

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
- Agent cards (thumbnails)
- Error/empty states

### SVG Source
- Primary: `public/images/activeagent-hero.svg` (500x500 viewBox)
- React component: `app/javascript/components/AgentAvatar.jsx`
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

### Buttons

| Style     | Lander Class        | Dashboard Tailwind                    |
|----------|--------------------|-----------------------------------------|
| Primary  | `button primary`   | `bg-red-500 text-white hover:bg-red-600 rounded-lg` |
| Secondary | `button secondary` | `border border-gray-300 text-gray-700 hover:bg-gray-50 rounded-lg` |
| Tertiary | `button tertiary`  | `bg-gray-100 text-gray-700 hover:bg-gray-200 rounded-lg` |
| Disabled | -                  | `bg-gray-200 text-gray-400 cursor-not-allowed` |

### Cards

| Context        | Lander                  | Dashboard                                |
|---------------|------------------------|-----------------------------------------|
| Feature card  | `.feature-card`        | `bg-white rounded-xl border border-gray-200` |
| Highlighted   | `.feature-card.highlighted` | `border-red-500 shadow-xl`          |
| Agent card    | -                      | `bg-white rounded-xl border border-gray-200 hover:border-gray-300` |

### Status Badges

| State      | Classes                           |
|-----------|----------------------------------|
| Active    | `bg-green-100 text-green-800`    |
| Trial     | `bg-blue-100 text-blue-800`     |
| Warning   | `bg-yellow-100 text-yellow-800`  |
| Error     | `bg-red-100 text-red-800`       |
| Inactive  | `bg-gray-100 text-gray-500`     |

### Focus States
- Input focus: `focus:ring-2 focus:ring-red-500 focus:border-transparent`
- Button focus: Same ring treatment
- Link focus: Underline + color shift

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
The dashboard currently uses light mode only with `bg-gray-50` background.

When adding dark mode to the dashboard, follow the lander's pattern:
- Recalculate background, text, and surface colors from the accent hue
- Adjust accent lightness for dark backgrounds (lighter accent on dark)
- Maintain the same hue (358) across both modes

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

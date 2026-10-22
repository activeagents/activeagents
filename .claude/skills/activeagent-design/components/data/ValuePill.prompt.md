Rank-tinted value pill for comparison cells. Full pill, mono 700, tabular numerals; tint from the semantic soft/text pairs. Carries the formatted value and a visually hidden rank word, so colour is never the only signal.

\`\`\`jsx
<ValuePill rank="good">65.3%</ValuePill>      // success-soft / success-text
<ValuePill rank="mid">28m 31s</ValuePill>     // warning-soft / warning-text
<ValuePill rank="poor">$10.53</ValuePill>     // error-soft / error-text
<ValuePill rank="none">n/a</ValuePill>        // muted / text-cell
<ValuePill rank="good" size="compact">0.92</ValuePill>  // 6px 12px, 13px text
\`\`\`

Rendered as `<span data-rank="good" class="value-pill">65.3% <span class="sr-only">best third</span></span>`. Default size 10px 16px / 15px text (marketing); `compact` for the dashboard. Never used for status words (that is `Badge`) or inside the identity cell.

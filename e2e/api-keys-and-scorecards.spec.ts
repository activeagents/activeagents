import { test, expect } from '@playwright/test';
// The session is established once by e2e/auth.setup.ts and reused via
// storageState, so no test signs in for itself.

// Covers the encrypted API key + provider credential settings flows, the
// agent scorecard cards, and the telemetry evaluation criteria.
//
// Runs against `bin/rails db:seed` — override with E2E_EMAIL / E2E_PASSWORD.
// The defaults used to be demo@activeagents.ai / demo-password-123, which no
// seed has ever created (the sibling checkout spec used the seeded pair), so
// every test here died in signIn before reaching an assertion.

// Seeded by db/seeds.rb. Not "Research Assistant" — that is an AgentTemplate
// name, and templates only render inside the Browse Templates modal.
const SEEDED_AGENT = 'Code Review Assistant';

const SHOTS = process.env.E2E_SHOTS_DIR;
const shot = async (page, name: string) => {
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/${name}.png` });
};

test.describe('API Keys settings', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/dashboard/settings');
    await page.getByRole('button', { name: 'API Keys' }).click();
  });

  test('creates a key, shows the token exactly once, then masks and revokes it', async ({ page }) => {
    const keyName = `e2e key ${Date.now()}`;
    await page.getByPlaceholder(/Key name/).fill(keyName);
    await page.getByRole('button', { name: '+ Create New Key' }).click();

    // Token panel: shown once, aa_-prefixed, with a copy button.
    const panel = page.locator('div', { hasText: /won't be shown again/ }).last();
    await expect(panel).toBeVisible();
    const token = (await panel.locator('code').innerText()).trim();
    expect(token).toMatch(/^aa_[A-Za-z0-9]{20,}$/);
    await shot(page, 'e2e-1-token-shown-once');

    await panel.getByRole('button', { name: 'Dismiss' }).click();
    await expect(page.locator('code')).toHaveCount(0);

    // The list shows the key masked — never the full token again.
    const row = page.locator('div.p-4.rounded-lg', { hasText: keyName }).first();
    await expect(row.getByText(/aa_.*…/)).toBeVisible();
    await expect(page.getByText(token)).toHaveCount(0);
    await shot(page, 'e2e-2-key-masked-in-list');

    // Revoke removes it.
    page.on('dialog', (dialog) => dialog.accept());
    await row.getByRole('button', { name: 'Revoke' }).click();
    await expect(page.getByText(keyName)).toHaveCount(0);
  });

  test('configures and removes a provider credential without echoing the key', async ({ page }) => {
    const row = page.locator('div.p-4.rounded-lg', { hasText: 'OpenRouter' }).first();
    await row.getByRole('button', { name: /Configure|Update/ }).click();
    await row.locator('input').fill('sk-or-e2e-secret-abc123');
    await row.getByRole('button', { name: 'Save' }).click();

    // Configured with a masked hint; the raw key never appears in the page.
    await expect(row.getByText(/Configured \(sk-o…c123\)/)).toBeVisible();
    await expect(page.getByText('sk-or-e2e-secret-abc123')).toHaveCount(0);
    await shot(page, 'e2e-3-provider-configured-masked');

    page.on('dialog', (dialog) => dialog.accept());
    await row.getByRole('button', { name: 'Remove' }).click();
    await expect(row.getByText('Not configured')).toBeVisible();
  });

  test('ollama credential is a host URL and is shown in full', async ({ page }) => {
    const row = page.locator('div.p-4.rounded-lg', { hasText: 'Ollama' }).first();
    await row.getByRole('button', { name: /Configure|Update/ }).click();
    // Host input is text (not password) with the localhost placeholder.
    const input = row.locator('input');
    await expect(input).toHaveAttribute('type', 'text');
    await input.fill('http://localhost:11434/v1');
    await row.getByRole('button', { name: 'Save' }).click();
    await expect(row.getByText('http://localhost:11434/v1', { exact: true })).toBeVisible();
  });
});

test.describe('Agent scorecards', () => {
  // Located by data-testid, not by Tailwind classes: the card was unified onto
  // AgentStatCard's inline styles, which removed div.bg-white.rounded-xl and
  // left the old locator matching zero elements — so every assertion below
  // failed on the first one while the mascot check passed vacuously.
  const cardFor = (page, name: string) =>
    page.locator(`[data-testid="agent-card"][data-agent-name="${name}"]`).first();

  test('agent cards show run, success, latency, eval, token and cost tiles', async ({ page }) => {
    await page.goto('/dashboard');

    const card = cardFor(page, SEEDED_AGENT);
    await expect(card).toBeVisible();
    for (const label of [/RUNS/i, /SUCCESS/i, /AVG TIME/i, /EVAL/i, /TOKENS/i, /COST/i]) {
      await expect(card.getByText(label)).toBeVisible();
    }
    // The mascot no longer heads every card — the scorecard carries the space.
    await expect(card.locator('svg[viewBox="0 0 500 500"]')).toHaveCount(0);
    await shot(page, 'e2e-4-scorecards');
  });

  // The point of removing fabricated seed data: an agent that has never run
  // must say so. This asserts the placeholder, where the previous version
  // asserted a "%" that only fabricated runs could have produced.
  test('an agent with no executions renders placeholders, not invented metrics', async ({ page }) => {
    await page.goto('/dashboard');

    const card = cardFor(page, SEEDED_AGENT);
    await expect(card).toBeVisible();
    await expect(card).toContainText('0');
    // Success, avg time, eval and cost all have nothing to report.
    expect(await card.getByText('—', { exact: true }).count()).toBeGreaterThan(0);
    await expect(card.getByText(/%$/)).toHaveCount(0);
    // Last activity replaces the config edit date only once something ran.
    await expect(card.getByText(/Updated /)).toBeVisible();
  });
});

test.describe('Telemetry evaluations', () => {
  test('form offers telemetry criteria and results tag telemetry sources', async ({ page }) => {
    await page.goto('/dashboard/evaluations');

    await page.getByRole('button', { name: /New Evaluation/i }).click();
    await expect(page.getByText('Telemetry criteria (trace aggregates)')).toBeVisible();
    await expect(page.getByText(/Trace error rate/)).toBeVisible();
    await expect(page.getByText(/Avg trace latency/)).toBeVisible();
    await shot(page, 'e2e-5-telemetry-criteria-form');
  });

  // Previously this clicked a "Production health" evaluation described as
  // seeded. No seed has ever created an Evaluation — that row existed only in
  // one developer's database, and its criteria are rule-based, so it has no
  // telemetry scores to find. The assertion was also satisfiable by the form
  // label "Telemetry criteria (trace aggregates)" left open by a Cancel click
  // wrapped in .catch(), so it could report success having proven nothing.
  //
  // Scoring a telemetry criterion requires ingested traces, which db:seed
  // deliberately does not fabricate. Rather than assert against a fixture that
  // does not exist, this skips visibly when there is nothing to check.
  test('telemetry-sourced scores are tagged in results', async ({ page }) => {
    await page.goto('/dashboard/evaluations');

    const telemetryEval = page
      .locator('[data-testid="evaluation-card"][data-telemetry="true"]')
      .first();
    await page.locator('[data-testid="evaluation-card"]').first().waitFor({ timeout: 10000 }).catch(() => {});
    test.skip(
      (await telemetryEval.count()) === 0,
      'no evaluation with telemetry criteria in this database — needs ingested traces, which db:seed does not fabricate'
    );

    await telemetryEval.click();
    // Scoped to a result row's source tag, not to the criteria form's label.
    await expect(page.getByTestId('score-source-telemetry').first()).toBeVisible();
    await shot(page, 'e2e-6-telemetry-scored-run');
  });
});

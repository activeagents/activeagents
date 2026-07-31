import { test, expect } from '@playwright/test';
import { signIn } from './helpers/auth';

// Covers the encrypted API key + provider credential settings flows, the
// agent scorecard cards, and the telemetry evaluation criteria.
//
// Requires a seeded account (see scripts/demo_seed via docs) — override with
// E2E_EMAIL / E2E_PASSWORD.
const USER = {
  email: process.env.E2E_EMAIL || 'demo@activeagents.ai',
  password: process.env.E2E_PASSWORD || 'demo-password-123',
};

const SHOTS = process.env.E2E_SHOTS_DIR;
const shot = async (page, name: string) => {
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/${name}.png` });
};

test.describe('API Keys settings', () => {
  test.beforeEach(async ({ page }) => {
    await signIn(page, USER);
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
  test('agent cards show run, success, latency and eval stats', async ({ page }) => {
    await signIn(page, USER);
    await page.goto('/dashboard');

    const card = page.locator('div.bg-white.rounded-xl', { hasText: 'Research Assistant' }).first();
    await expect(card.getByText(/RUNS/i)).toBeVisible();
    await expect(card.getByText(/SUCCESS/i)).toBeVisible();
    await expect(card.getByText(/AVG TIME/i)).toBeVisible();
    await expect(card.getByText(/EVAL/i)).toBeVisible();
    // Seeded data renders real numbers, not placeholders.
    await expect(card.getByText(/%$/).first()).toBeVisible();
    await shot(page, 'e2e-4-scorecards');
  });
});

test.describe('Telemetry evaluations', () => {
  test('form offers telemetry criteria and results tag telemetry sources', async ({ page }) => {
    await signIn(page, USER);
    await page.goto('/dashboard/evaluations');

    await page.getByRole('button', { name: /New Evaluation/i }).click();
    await expect(page.getByText('Telemetry criteria (trace aggregates)')).toBeVisible();
    await expect(page.getByText(/Trace error rate/)).toBeVisible();
    await expect(page.getByText(/Avg trace latency/)).toBeVisible();
    await shot(page, 'e2e-5-telemetry-criteria-form');

    // The seeded "Production health" evaluation shows telemetry-scored rows.
    await page.getByRole('button', { name: /Cancel|Close/i }).first().click().catch(() => {});
    await page.getByText('Production health').first().click();
    await expect(page.getByText('telemetry').first()).toBeVisible();
    await shot(page, 'e2e-6-telemetry-scored-run');
  });
});

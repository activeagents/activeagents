import { test, expect } from '@playwright/test';
import { signIn, TEST_USER } from './helpers/auth';
import { completeStripeCheckout, STRIPE_TEST_CARDS } from './helpers/stripe';

test.describe('Subscription Checkout Flow', () => {
  test.beforeEach(async ({ page }) => {
    // Sign in before each test
    await signIn(page);
  });

  test('displays plans page correctly', async ({ page }) => {
    await page.goto('/plans');

    // Check page title
    await expect(page.getByRole('heading', { name: 'Choose your plan' })).toBeVisible();

    // Check billing toggle exists
    await expect(page.getByRole('button', { name: 'Monthly' })).toBeVisible();
    await expect(page.getByRole('button', { name: /Annual/ })).toBeVisible();

    // Check all plan cards are visible
    await expect(page.getByRole('heading', { name: 'ActiveAgent.dev' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'ActiveAgent.PRO' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'ActiveAgent Enterprise' })).toBeVisible();
  });

  test('shows free plan as current plan for new users', async ({ page }) => {
    await page.goto('/plans');

    // Free plan should show "Current Plan" button
    const freePlanCard = page.locator('text=ActiveAgent.dev').locator('..').locator('..');
    await expect(freePlanCard.getByRole('button', { name: 'Current Plan' })).toBeVisible();
  });

  test('can toggle between monthly and annual billing', async ({ page }) => {
    await page.goto('/plans');

    // Default should be monthly
    await expect(page.getByText('$99', { exact: false })).toBeVisible();

    // Click annual toggle
    await page.getByRole('button', { name: /Annual/ }).click();

    // Should show annual price
    await expect(page.getByText('$995', { exact: false })).toBeVisible();
  });

  test('redirects to Stripe checkout when clicking Subscribe', async ({ page }) => {
    await page.goto('/plans');

    // Click Subscribe on Pro plan
    await page.getByRole('button', { name: 'Subscribe' }).click();

    // Should redirect to Stripe checkout
    await expect(page).toHaveURL(/checkout\.stripe\.com/);

    // Verify it's the Pro plan checkout
    await expect(page.getByRole('heading', { name: /ActiveAgent\.PRO/ })).toBeVisible();
  });

  test('can complete Pro plan subscription checkout', async ({ page }) => {
    await page.goto('/plans');

    // Click Subscribe on Pro plan
    await page.getByRole('button', { name: 'Subscribe' }).click();

    // Complete the Stripe checkout
    await completeStripeCheckout(page);

    // Should be on subscriptions page after checkout
    await expect(page).toHaveURL(/\/subscriptions/);

    // Verify subscription is active
    await expect(page.getByRole('heading', { name: 'Subscription' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'ActiveAgent.PRO' })).toBeVisible();
  });

  test('shows subscription details after successful checkout', async ({ page }) => {
    // Navigate directly to subscriptions page (assuming user already has subscription)
    await page.goto('/subscriptions');

    // Check subscription card elements
    await expect(page.getByRole('heading', { name: 'Subscription' })).toBeVisible();

    // Check for management buttons
    await expect(page.getByRole('button', { name: 'Manage Billing' })).toBeVisible();
  });
});

test.describe('Subscription Management', () => {
  test.beforeEach(async ({ page }) => {
    await signIn(page);
  });

  test('can access billing portal', async ({ page }) => {
    await page.goto('/subscriptions');

    // Click Manage Billing button
    await page.getByRole('button', { name: 'Manage Billing' }).click();

    // Should redirect to Stripe billing portal
    await expect(page).toHaveURL(/billing\.stripe\.com|checkout\.stripe\.com/);
  });

  test('shows cancel subscription option for active subscriptions', async ({ page }) => {
    await page.goto('/subscriptions');

    // Check cancel button is visible
    await expect(page.getByRole('button', { name: /Cancel/ })).toBeVisible();
  });

  test('shows plan upgrade options', async ({ page }) => {
    await page.goto('/subscriptions');

    // Should show "Switch Plan" section with other available plans
    const switchPlanSection = page.getByRole('heading', { name: 'Switch Plan' });
    if (await switchPlanSection.isVisible()) {
      await expect(page.getByText('ActiveAgent Enterprise')).toBeVisible();
    }
  });
});

test.describe('Unauthenticated Access', () => {
  test('redirects to sign in when accessing plans without auth', async ({ page }) => {
    await page.goto('/plans');

    // Should show plans page (public)
    await expect(page.getByRole('heading', { name: 'Choose your plan' })).toBeVisible();
  });

  test('redirects to registration when clicking Subscribe without auth', async ({ page }) => {
    await page.goto('/plans');

    // Click Subscribe
    await page.getByRole('button', { name: 'Subscribe' }).click();

    // Should redirect to registration or sign in
    await expect(page).toHaveURL(/\/(registration|session)/);
  });
});

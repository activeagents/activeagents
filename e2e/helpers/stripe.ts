import { Page } from '@playwright/test';

/**
 * Stripe test card numbers for different scenarios
 */
export const STRIPE_TEST_CARDS = {
  success: '4242424242424242',
  declined: '4000000000000002',
  insufficientFunds: '4000000000009995',
  requiresAuth: '4000002500003155',
};

/**
 * Fill Stripe Checkout card form
 * Handles the complexities of Stripe's checkout form including:
 * - Clicking to expand the Card payment method
 * - Filling card number, expiry, CVC
 * - Filling billing address fields
 */
export async function fillStripeCheckoutForm(
  page: Page,
  options: {
    cardNumber?: string;
    expiry?: string;
    cvc?: string;
    name?: string;
    zip?: string;
    uncheckSaveInfo?: boolean;
  } = {}
) {
  const {
    cardNumber = STRIPE_TEST_CARDS.success,
    expiry = '12/34',
    cvc = '123',
    name = 'Test User',
    zip = '12345',
    uncheckSaveInfo = true,
  } = options;

  // Wait for Stripe checkout to load
  await page.waitForURL(/checkout\.stripe\.com/);
  await page.waitForTimeout(1000);

  // Click to expand the Card payment method accordion
  await page.evaluate(() => {
    const cardButton = document.querySelector('[data-testid="card-accordion-item-button"]');
    if (cardButton) {
      (cardButton as HTMLElement).click();
    }
  });
  await page.waitForTimeout(1000);

  // Fill card fields
  await page.getByRole('textbox', { name: 'Card number' }).fill(cardNumber);
  await page.getByRole('textbox', { name: 'Expiration' }).fill(expiry);
  await page.getByRole('textbox', { name: 'CVC' }).fill(cvc);
  await page.getByRole('textbox', { name: 'Cardholder name' }).fill(name);
  await page.getByRole('textbox', { name: 'ZIP' }).fill(zip);

  // Uncheck "Save my information" if requested
  if (uncheckSaveInfo) {
    const checkbox = page.getByRole('checkbox', { name: 'Save my information' });
    if (await checkbox.isChecked()) {
      await checkbox.click();
    }
  }
}

/**
 * Submit the Stripe checkout form and wait for redirect
 */
export async function submitStripeCheckout(page: Page) {
  // Click the submit button
  await page.getByTestId('hosted-payment-submit-button').click();

  // Wait for the page to redirect back to our app
  await page.waitForURL(/localhost:3000/, { timeout: 30000 });
}

/**
 * Complete the full Stripe checkout flow
 */
export async function completeStripeCheckout(
  page: Page,
  options?: Parameters<typeof fillStripeCheckoutForm>[1]
) {
  await fillStripeCheckoutForm(page, options);
  await submitStripeCheckout(page);
}

import { Page } from '@playwright/test';

/**
 * Default test user credentials
 */
export const TEST_USER = {
  email: 'demo@example.com',
  password: 'password123',
};

/**
 * Sign in a user
 */
export async function signIn(
  page: Page,
  credentials: { email: string; password: string } = TEST_USER
) {
  await page.goto('/session/new');

  // Fill in credentials
  await page.getByRole('textbox', { name: 'email' }).fill(credentials.email);
  await page.getByRole('textbox', { name: 'password' }).fill(credentials.password);

  // Submit the form
  await page.getByRole('button', { name: 'Sign in' }).click();

  // Wait for redirect after sign in
  await page.waitForURL(/\/(dashboard|plans|$)/);
}

/**
 * Sign out the current user
 */
export async function signOut(page: Page) {
  // Navigate to a page with logout functionality
  await page.goto('/dashboard');

  // Look for and click logout button/link
  const logoutButton = page.getByRole('button', { name: /sign out|logout/i });
  if (await logoutButton.isVisible()) {
    await logoutButton.click();
    await page.waitForURL('/');
  }
}

/**
 * Create a new user via registration
 */
export async function registerUser(
  page: Page,
  userData: { email: string; password: string }
) {
  await page.goto('/registration/new');

  await page.getByRole('textbox', { name: 'email' }).fill(userData.email);
  await page.getByRole('textbox', { name: 'password' }).fill(userData.password);

  // If there's a password confirmation field
  const confirmField = page.getByRole('textbox', { name: /confirm/i });
  if (await confirmField.isVisible()) {
    await confirmField.fill(userData.password);
  }

  await page.getByRole('button', { name: /sign up|register|create/i }).click();

  await page.waitForURL(/\/(dashboard|plans)/);
}

import { test as setup, expect } from '@playwright/test';
import { signIn, TEST_USER } from './helpers/auth';

// Sign in once for the whole run and reuse the session.
//
// Every test used to sign in for itself. SessionsController rate-limits
// creates to 10 per 3 minutes (app/controllers/sessions_controller.rb:3), and
// the suite makes sixteen — so a full run redirected back to /session/new with
// "Try again later." and tests failed in waitForURL, looking like assertion
// failures. Retries made it worse, not better.
//
// Tests that need a signed-out browser opt out with:
//   test.use({ storageState: { cookies: [], origins: [] } })

export const STORAGE_STATE = 'e2e/.auth/user.json';

setup('authenticate', async ({ page }) => {
  const user = {
    email: process.env.E2E_EMAIL || TEST_USER.email,
    password: process.env.E2E_PASSWORD || TEST_USER.password,
  };

  await signIn(page, user);
  // Sign-in lands on /, /dashboard or /plans depending on account state, so
  // the check is that we left the form — not where we landed.
  await expect(page).not.toHaveURL(/\/session\/new/);

  await page.context().storageState({ path: STORAGE_STATE });
});

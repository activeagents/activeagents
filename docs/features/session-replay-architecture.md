# Session Replay Architecture

## Overview

The session replay feature demonstrates Active Agent's browser automation capabilities by showing an agent navigating the lander and signing up for the newsletter. The demo runs in the hero section using a hybrid approach:

1. **Pre-recorded replay** - Shows a real recording from an agent browsing the lander
2. **Live iframe** - Displays the actual lander scaled down in a mock browser
3. **Handoff to user** - When the agent reaches the newsletter form, the user can take over and sign up on the real page

## Components

### Frontend

- **`app/views/pages/sections/_hero.html.erb`** - Hero section with session replay demo
- **`app/javascript/controllers/session_replay_controller.js`** - Stimulus controller for playback
- **`app/assets/stylesheets/landing/base.css`** - Styles for the session replay UI

### Backend

- **`SessionRecording`** model - Stores recordings with actions and screenshots
- **`SessionRecordingService`** - Service for recording browser actions
- **`MCPRecordingMiddleware`** - Intercepts Playwright MCP calls to record them
- **`IncusSandboxService`** - Manages Incus container sandboxes

### API

- **`GET /api/session_recordings/demo`** - Fetches the demo recording for playback
- **`POST /api/session_recordings/:id/handoff`** - Gets handoff state for session continuation

## Demo Modes

### 1. Iframe Mode (Current)

Shows the real lander in a scaled iframe with an agent cursor overlay:

```html
<div class="browser-viewport-hero">
  <iframe src="/?demo_mode=true" class="lander-iframe"></iframe>
  <div class="agent-cursor">Agent</div>
</div>
```

The `demo_mode=true` param prevents infinite recursion by hiding the session replay in the iframe.

### 2. Newsletter Mode (Legacy)

Shows a mini version of the lander with simulated content:

```html
<div class="demo-page-content">
  <div class="demo-section demo-hero">...</div>
  <div class="demo-section demo-features">...</div>
  <div class="demo-section demo-newsletter">...</div>
</div>
```

## Recording Sessions

### Using Mock Data

```bash
bin/rails session_replay:seed_demo
```

Creates a demo recording with predefined actions (no Playwright required).

### Using Real Playwright

```bash
# Start Playwright MCP server
npx @anthropic-ai/playwright-mcp

# Record the demo session
PLAYWRIGHT_MCP_HOST=localhost PLAYWRIGHT_MCP_PORT=3001 bin/rails session_replay:record_lander_demo
```

This connects to a running Playwright MCP server and records real browser interactions.

## Handoff Flow

The handoff is lightweight - no sandbox required. The user simply takes over locally while we continue recording:

1. Agent cursor moves through the lander in the iframe
2. At the newsletter section, handoff overlay appears
3. User clicks "Go to Newsletter"
4. Page scrolls to the real newsletter section (`#newsletter`)
5. **Recording continues** - user interactions are captured in the trace log
6. User enters their email and submits the real form

### User Interaction Recording

During handoff, we track:
- Scroll position changes
- Email input focus/typing
- Form submissions

This enables future **agent handback** scenarios where:
- User gets stuck or needs help
- Agent can resume from user's last recorded state
- Collaborative human-agent workflows

### Future: Live Sandbox Sessions

For more complex workflows (agent booking a flight, filling complex forms):

1. User clicks "Take Over"
2. Backend spins up an Incus sandbox with Playwright
3. noVNC or websocket streams the sandbox browser to user
4. User interacts with live browser in sandbox
5. Interactions recorded for agent handback
6. Sandbox terminates after timeout

## Files Changed

- `app/views/pages/sections/_hero.html.erb` - Added iframe mode, demo_mode handling
- `app/javascript/controllers/session_replay_controller.js` - Added iframe mode support, takeOverNewsletter
- `app/controllers/pages_controller.rb` - Added demo_mode param
- `lib/tasks/session_replay.rake` - Updated for newsletter demo, added real recording task
- `app/assets/stylesheets/landing/base.css` - Added iframe styles, fixed nav scrolling

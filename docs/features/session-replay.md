# Session Replay - Pro Feature

## Overview

Session Replay records browser interactions from AI agents using browser automation (Playwright MCP, Selenium, etc.) and provides VCR-style playback for debugging, verification, and compliance.

**Tier:** Pro ($995/yr) and Enterprise

## Core Concept

When an agent uses browser automation tools, Session Replay captures:
- Screenshots at key moments (navigation, form fills, clicks)
- DOM snapshots for replay without re-execution
- Action timeline with timestamps
- Network requests (optional)
- Console logs

Think "FullStory for AI agents" - watch exactly what the agent did, debug failures, verify completions.

## Architecture

### Recording Flow

```
Agent Action (Playwright MCP)
    │
    ▼
┌─────────────────────────────────┐
│   Session Replay Middleware      │
│   (intercepts browser actions)   │
└─────────────────────────────────┘
    │
    ├─► Screenshot capture
    ├─► DOM snapshot
    ├─► Action metadata
    │
    ▼
┌─────────────────────────────────┐
│   Session Storage               │
│   (S3/GCS + metadata in DB)     │
└─────────────────────────────────┘
```

### Data Model

```ruby
# db/migrate/XXXX_create_session_recordings.rb
class CreateSessionRecordings < ActiveRecord::Migration[7.2]
  def change
    create_table :session_recordings do |t|
      t.references :agent_execution, null: false
      t.string :name # e.g., "checkout_flow"
      t.string :status # recording, completed, failed
      t.integer :duration_ms
      t.integer :action_count
      t.json :metadata
      t.timestamps
    end

    create_table :recording_actions do |t|
      t.references :session_recording, null: false
      t.string :action_type # navigate, click, type, snapshot, scroll
      t.integer :sequence
      t.integer :timestamp_ms
      t.string :selector # CSS selector or element ref
      t.text :value # typed text, url, etc.
      t.string :screenshot_key # S3/GCS key
      t.string :dom_snapshot_key
      t.json :metadata
      t.timestamps
    end

    create_table :recording_snapshots do |t|
      t.references :session_recording, null: false
      t.references :recording_action
      t.string :storage_key
      t.string :snapshot_type # screenshot, dom, full_page
      t.integer :width
      t.integer :height
      t.integer :file_size_bytes
      t.timestamps
    end
  end
end
```

### Storage Strategy

- **Screenshots:** Store in cloud storage (S3/GCS) with signed URLs for playback
- **DOM Snapshots:** Compressed HTML stored in cloud storage
- **Metadata:** PostgreSQL for fast querying
- **Retention:**
  - Pro: 14 days (matches trace retention)
  - Enterprise: 400 days

## Implementation Phases

### Phase 1: Recording Infrastructure

1. **MCP Integration**
   - Intercept Playwright MCP tool calls (browser_click, browser_type, browser_navigate, browser_snapshot)
   - Capture screenshots after each action
   - Store action metadata with timing

2. **Storage Service**
   ```ruby
   class SessionRecordingService
     def start_recording(agent_execution:, name:)
     def record_action(type:, selector:, value:, screenshot:)
     def capture_snapshot(type: :screenshot)
     def complete_recording
   end
   ```

3. **Background Processing**
   - Screenshots compressed and uploaded async
   - DOM snapshots captured on demand (not every action)

### Phase 2: Playback UI

1. **Session List View**
   - Filter by agent, status, date
   - Search by session name
   - Quick preview thumbnails

2. **Replay Player**
   - Timeline scrubber with action markers
   - Play/pause/step controls
   - Speed control (0.5x, 1x, 2x)
   - Screenshot viewer with zoom
   - Action panel showing what happened

3. **Components** (React)
   ```
   components/dashboard/
   ├── SessionReplayList.jsx
   ├── SessionReplayPlayer.jsx
   ├── ReplayTimeline.jsx
   ├── ReplayViewport.jsx
   └── ActionPanel.jsx
   ```

### Phase 3: Pro Integration

1. **VCR-style Export**
   - Export sessions as "cassettes" for test fixtures
   - Import cassettes for deterministic replay
   - Format: JSON with base64 screenshots or references

2. **Comparison Mode**
   - Compare two recordings side-by-side
   - Highlight differences in actions/outcomes
   - Useful for A/B testing agent prompts

3. **Alerts & Annotations**
   - Flag failed sessions automatically
   - Allow manual annotations ("Bug here", "Expected behavior")
   - Integration with trace timeline

## API Endpoints

```ruby
# config/routes.rb
namespace :api do
  resources :session_recordings, only: [:index, :show, :destroy] do
    member do
      get :actions
      get :snapshot/:action_id, action: :snapshot
      post :export
    end
    collection do
      get :recent
    end
  end
end
```

## UI Mockup Reference

The lander preview (`_product_preview.html.erb :session_replay`) already shows the target UI:
- Browser chrome with recording indicator
- Viewport with agent cursor
- Action list sidebar (completed/active/pending)
- Timeline with snapshot markers
- Playback controls

## Billing Considerations

- **Storage:** Count against trace storage limits
- **Snapshots:** Each screenshot ~100KB avg, count as ~1 trace unit
- **Overages:** $2.00/1k additional traces (Pro), $1.50/1k (Enterprise)

## Security

- Screenshots may contain sensitive data (passwords, PII)
- Auto-redact known sensitive fields (credit card, SSN patterns)
- Encryption at rest (AES-256)
- Signed URLs with short expiry (15 min)
- Access control: Only workspace members can view recordings

## Dependencies

- ActiveStorage for file handling
- ImageMagick for screenshot compression
- Optional: rrweb for DOM recording (future enhancement)

## Success Metrics

- Recording capture rate (target: 99%+)
- Playback load time (target: <2s for timeline)
- Storage efficiency (target: <500KB avg per session)
- User engagement: Sessions viewed / Sessions recorded

## Implementation Status

### Completed

**Phase 1: Recording Infrastructure**
- Database migrations (`db/migrate/20260324000005_create_session_recordings.rb`)
  - `session_recordings` - Main recording model
  - `recording_actions` - Individual browser actions
  - `recording_snapshots` - Screenshots and DOM snapshots
- `SessionRecording` model (`app/models/session_recording.rb`)
- `RecordingAction` model (`app/models/recording_action.rb`)
- `RecordingSnapshot` model with ActiveStorage (`app/models/recording_snapshot.rb`)
- `SessionRecordingService` (`app/services/session_recording_service.rb`)
- `MCPRecordingMiddleware` for Playwright MCP integration (`app/services/mcp_recording_middleware.rb`)
- `SessionRecordable` concern for models (`app/models/concerns/session_recordable.rb`)

**Phase 2: API & Playback UI**
- API Controller (`app/controllers/api/session_recordings_controller.rb`)
  - `GET /api/session_recordings` - List recordings
  - `GET /api/session_recordings/recent` - Recent recordings
  - `GET /api/session_recordings/demo` - Demo recording for lander
  - `GET /api/session_recordings/:id` - Recording details
  - `GET /api/session_recordings/:id/actions` - Action timeline
  - `GET /api/session_recordings/:id/snapshot/:action_id` - Get screenshot/DOM
  - `POST /api/session_recordings/:id/export` - Export as VCR cassette
  - `POST /api/session_recordings/:id/handoff` - Get handoff state
- Dashboard components:
  - `SessionReplayView.jsx` - Full playback UI with timeline
  - Navigation added to sidebar
  - Route `/dashboard/replay` configured

**Phase 3: Lander Demo with Handoff**
- `SessionReplayDemo.jsx` - Interactive demo component for landing page
- Shows pre-recorded agent session
- Handoff prompt when agent pauses
- User interactions tracked in trace log
- Integrated with trace analytics

### Key Features

1. **Recording**: Automatic capture of browser actions via MCP middleware
2. **Playback**: VCR-style timeline with screenshots and action markers
3. **Handoff**: Users can take over from where agents stopped
4. **Trace Integration**: User interactions after handoff appear in trace logs
5. **Security**: Auto-redaction of sensitive fields (passwords, credit cards)
6. **Export**: VCR cassette format for test fixtures

### Usage

```ruby
# Start recording
recording = SessionRecordingService.start(sandbox_session: session)

# Record actions (via MCPRecordingMiddleware)
middleware = MCPRecordingMiddleware.new(session_recording: recording)
middleware.intercept(tool_name: "browser_click", parameters: { ref: "#submit" }) do
  # Execute actual MCP tool
end

# Capture handoff state
middleware.capture_for_handoff(
  url: current_url,
  cookies: browser_cookies,
  form_values: { email: "user@..." }
)

# Complete recording
recording.complete!
```

### Next Steps

- [ ] Connect to live Playwright MCP tools in sandbox container
- [ ] Implement rrweb for DOM recording
- [ ] Add comparison mode for A/B testing
- [ ] Set up cloud storage for production (GCS)

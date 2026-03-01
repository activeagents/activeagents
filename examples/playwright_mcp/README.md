# PlaywrightMCP Demo Agent

A sample agent demonstrating browser automation using Playwright MCP (Model Context Protocol).

## Overview

This example shows how to create an AI agent that can:
- Navigate web pages
- Take screenshots
- Extract content from pages
- Fill forms and interact with elements
- Perform web scraping and testing

## Running Locally

```bash
# Install dependencies
npm install @anthropic/mcp-server-playwright

# Set your API key
export ANTHROPIC_API_KEY=your_key_here

# Run the example
ruby examples/playwright_mcp/demo_agent.rb
```

## Running on Active Agents Platform

Free users can try this agent at https://activeagents.ai/dashboard/sandbox

The platform provides:
- Ephemeral Cloud Run containers for isolated execution
- No account required for basic usage
- 15-minute sessions with up to 10 runs
- Real-time output streaming

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Active Agents Platform                      │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────┐  │
│  │  React UI   │───▶│  Cloud Run   │───▶│    Browser     │  │
│  │ (Dashboard) │    │   Sandbox    │    │   (Chromium)   │  │
│  └─────────────┘    └──────────────┘    └────────────────┘  │
│                              │                               │
│                              ▼                               │
│                     ┌──────────────┐                        │
│                     │  Anthropic   │                        │
│                     │     API      │                        │
│                     └──────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

## Example Tasks

### 1. Screenshot a Page
```
"Take a screenshot of https://example.com"
```

### 2. Extract Content
```
"Go to https://news.ycombinator.com and list the top 5 stories"
```

### 3. Form Interaction
```
"Navigate to the login page and describe the form fields"
```

### 4. Multi-Step Navigation
```
"Search for 'AI agents' on Wikipedia and summarize the first paragraph"
```

## Security Notes

- The agent runs in an isolated Cloud Run container with gVisor
- Network access is limited to standard web ports
- No persistent storage between sessions
- Sessions timeout after 15 minutes of inactivity
- Resource limits enforced by Cloud Run

## Configuration

Environment variables:
- `ANTHROPIC_API_KEY` - Required API key for Claude
- `MAX_STEPS` - Maximum agent steps (default: 10)
- `TIMEOUT` - Browser timeout in seconds (default: 30)
- `HEADLESS` - Run browser headless (default: true)

## Free Tier Limits

| Limit | Value |
|-------|-------|
| Max Runs | 10 per session |
| Timeout | 300s per task |
| Session Duration | 15 minutes |
| Max Tokens | 50,000 per session |

## Sandbox Container

The sandbox container (`sandbox/Dockerfile`) includes:
- Ruby 3.4.1 runtime
- Node.js 20 for Playwright MCP server
- Chromium browser
- Sinatra server for handling requests

# frozen_string_literal: true

# PlaywrightMCP Demo Agent
#
# This agent demonstrates browser automation using Playwright MCP.
# It can navigate websites, take screenshots, extract content, and interact with pages.
#
# Usage:
#   agent = PlaywrightMCPDemoAgent.new
#   response = agent.execute("Take a screenshot of https://example.com")
#   puts response.content
#
# Prerequisites:
#   - npm install @anthropic/mcp-server-playwright
#   - ANTHROPIC_API_KEY environment variable

require "active_agent"

class PlaywrightMCPDemoAgent < ApplicationAgent
  generate_with :anthropic,
    model: "claude-sonnet-5",
    mcp_servers: {
      playwright: {
        command: "npx",
        args: [ "-y", "@anthropic/mcp-server-playwright" ],
        env: {
          "PLAYWRIGHT_HEADLESS" => ENV.fetch("HEADLESS", "true"),
          "PLAYWRIGHT_TIMEOUT" => ENV.fetch("TIMEOUT", "30000")
        }
      }
    }

  # Maximum steps to prevent infinite loops
  MAX_STEPS = ENV.fetch("MAX_STEPS", 10).to_i

  def browse
    prompt(
      instructions: browser_instructions,
      message: params[:task],
      temperature: 0.2,
      max_tokens: 4096
    )
  end

  def screenshot
    prompt(
      instructions: screenshot_instructions,
      message: "Take a screenshot of: #{params[:url]}",
      temperature: 0.1
    )
  end

  def extract
    prompt(
      instructions: extraction_instructions,
      message: "Extract the following from #{params[:url]}: #{params[:selector]}",
      temperature: 0.2
    )
  end

  private

  def browser_instructions
    <<~INSTRUCTIONS
      You are a browser automation assistant using Playwright MCP.

      Available actions:
      - browser_navigate: Go to a URL
      - browser_snapshot: Get the accessibility tree of current page
      - browser_click: Click on an element (use ref from snapshot)
      - browser_type: Type text into an input
      - browser_take_screenshot: Capture the current page
      - browser_wait_for: Wait for text or element

      Guidelines:
      1. Always take a snapshot first to understand the page structure
      2. Use element refs from snapshots for interactions
      3. Wait for page loads before taking actions
      4. Handle errors gracefully and explain what went wrong
      5. Limit yourself to #{MAX_STEPS} steps maximum

      When taking screenshots, save them with descriptive names.
      Always describe what you see and what actions you're taking.
    INSTRUCTIONS
  end

  def screenshot_instructions
    <<~INSTRUCTIONS
      You are a screenshot assistant. Your job is to:
      1. Navigate to the provided URL using browser_navigate
      2. Wait for the page to load completely
      3. Take a screenshot using browser_take_screenshot
      4. Describe what's visible in the screenshot

      Be concise in your descriptions and note any loading issues.
    INSTRUCTIONS
  end

  def extraction_instructions
    <<~INSTRUCTIONS
      You are a web content extractor. Your job is to:
      1. Navigate to the provided URL
      2. Take a snapshot to understand the page structure
      3. Extract the requested information
      4. Format the data clearly

      If the requested data isn't found, explain what is available instead.
    INSTRUCTIONS
  end
end

# Example tasks for demonstration
module PlaywrightMCPExamples
  SAMPLE_TASKS = [
    {
      name: "Screenshot Example.com",
      task: "Take a screenshot of https://example.com",
      description: "Navigate to example.com and capture a screenshot"
    },
    {
      name: "Extract Hacker News Headlines",
      task: "Go to https://news.ycombinator.com and list the top 5 story titles with their scores",
      description: "Scrape the front page of Hacker News"
    },
    {
      name: "Check Wikipedia",
      task: "Navigate to https://en.wikipedia.org/wiki/Artificial_intelligence and extract the first paragraph of the article",
      description: "Extract content from Wikipedia"
    },
    {
      name: "GitHub Trending",
      task: "Visit https://github.com/trending and list the top 3 trending repositories",
      description: "Check GitHub's trending repositories"
    },
    {
      name: "Weather Check",
      task: "Go to https://weather.gov and describe the current layout and main elements",
      description: "Analyze a weather website's structure"
    }
  ].freeze

  def self.run_demo(task_index = 0)
    task = SAMPLE_TASKS[task_index]
    puts "Running demo: #{task[:name]}"
    puts "Description: #{task[:description]}"
    puts "-" * 50

    agent = PlaywrightMCPDemoAgent.new
    response = agent.with(task: task[:task]).browse.generate_now

    puts "Result:"
    puts response.content
    response
  end
end

# Run if executed directly
if __FILE__ == $PROGRAM_NAME
  puts "PlaywrightMCP Demo Agent"
  puts "=" * 50

  if ENV["ANTHROPIC_API_KEY"].nil?
    puts "Error: ANTHROPIC_API_KEY environment variable is required"
    exit 1
  end

  task_index = ARGV[0]&.to_i || 0
  PlaywrightMCPExamples.run_demo(task_index)
end

# frozen_string_literal: true

namespace :session_replay do
  desc "Record a real lander demo session using Playwright"
  task record_lander_demo: :environment do
    require "net/http"
    require "json"
    require "base64"
    require "fileutils"

    puts "Recording lander demo session..."

    # Ensure tmp directory exists for screenshots
    screenshots_dir = Rails.root.join("tmp", "demo_screenshots")
    FileUtils.mkdir_p(screenshots_dir)

    # Remove existing demo recording
    SessionRecording.where(name: "lander_demo").destroy_all

    # Create the demo recording
    recording = SessionRecording.create!(
      name: "lander_demo",
      status: :recording,
      action_count: 0,
      metadata: {
        started_at: Time.current.iso8601,
        description: "Agent browsing Active Agent lander for newsletter signup",
        demo_type: "newsletter"
      }
    )

    recording_service = SessionRecordingService.new(recording)

    begin
      # Connect to Playwright MCP server (assuming it's running)
      playwright_host = ENV.fetch("PLAYWRIGHT_MCP_HOST", "localhost")
      playwright_port = ENV.fetch("PLAYWRIGHT_MCP_PORT", "3001")

      puts "Connecting to Playwright MCP at #{playwright_host}:#{playwright_port}..."

      # Helper to call Playwright MCP tools
      def call_playwright(host, port, tool_name, params = {})
        uri = URI("http://#{host}:#{port}/mcp/v1/tools/call")
        http = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = 30

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = {
          name: tool_name,
          arguments: params
        }.to_json

        response = http.request(request)
        JSON.parse(response.body) if response.code == "200"
      rescue => e
        puts "Playwright call failed: #{e.message}"
        nil
      end

      # Helper to take screenshot and save
      def capture_screenshot(host, port, screenshots_dir, name)
        result = call_playwright(host, port, "browser_take_screenshot", { type: "png" })
        if result && result["content"]
          # Extract base64 image data
          image_data = result["content"].find { |c| c["type"] == "image" }
          if image_data
            filename = "#{name}.png"
            filepath = File.join(screenshots_dir, filename)
            File.write(filepath, Base64.decode64(image_data["data"]))
            puts "  Screenshot saved: #{filename}"
            return filepath
          end
        end
        nil
      end

      # Step 1: Navigate to lander
      puts "\nStep 1: Navigating to activeagents.ai..."
      call_playwright(playwright_host, playwright_port, "browser_navigate", {
        url: "https://activeagents.ai"
      })
      sleep 2

      screenshot = capture_screenshot(playwright_host, playwright_port, screenshots_dir, "01_initial")
      recording_service.navigate(
        url: "https://activeagents.ai",
        screenshot: screenshot ? File.read(screenshot) : nil
      )

      # Step 2: Take initial snapshot
      puts "\nStep 2: Taking initial snapshot..."
      call_playwright(playwright_host, playwright_port, "browser_snapshot", {})
      screenshot = capture_screenshot(playwright_host, playwright_port, screenshots_dir, "02_snapshot")
      recording_service.capture_snapshot(
        screenshot: screenshot ? File.read(screenshot) : nil
      )
      sleep 1

      # Step 3: Scroll down to see features
      puts "\nStep 3: Scrolling to features section..."
      call_playwright(playwright_host, playwright_port, "browser_evaluate", {
        function: "() => window.scrollBy(0, 400)"
      })
      sleep 1
      screenshot = capture_screenshot(playwright_host, playwright_port, screenshots_dir, "03_features")
      recording_service.scroll(
        position: { y: 400 },
        screenshot: screenshot ? File.read(screenshot) : nil
      )

      # Step 4: Scroll to newsletter section
      puts "\nStep 4: Scrolling to newsletter section..."
      call_playwright(playwright_host, playwright_port, "browser_evaluate", {
        function: "() => { const el = document.querySelector('#newsletter'); if(el) el.scrollIntoView({ behavior: 'smooth' }); }"
      })
      sleep 1.5
      screenshot = capture_screenshot(playwright_host, playwright_port, screenshots_dir, "04_newsletter")
      recording_service.scroll(
        position: { y: 800 },
        screenshot: screenshot ? File.read(screenshot) : nil
      )

      # Step 5: Click on email input
      puts "\nStep 5: Clicking email input..."
      # Get page snapshot to find the email input ref
      snapshot_result = call_playwright(playwright_host, playwright_port, "browser_snapshot", {})
      # Find email input ref from snapshot (this would need parsing in real implementation)
      email_ref = "newsletter-email" # Placeholder - would extract from snapshot

      call_playwright(playwright_host, playwright_port, "browser_click", {
        ref: email_ref,
        element: "Email input field"
      })
      sleep 0.5
      screenshot = capture_screenshot(playwright_host, playwright_port, screenshots_dir, "05_click_email")
      recording_service.click(
        selector: "#newsletter-email",
        screenshot: screenshot ? File.read(screenshot) : nil
      )

      # Step 6: Type email address (agent stops here for handoff)
      puts "\nStep 6: Typing email address..."
      call_playwright(playwright_host, playwright_port, "browser_type", {
        ref: email_ref,
        text: "you@example.com",
        slowly: true
      })
      sleep 2
      screenshot = capture_screenshot(playwright_host, playwright_port, screenshots_dir, "06_type_email")
      recording_service.type(
        selector: "#newsletter-email",
        text: "you@example.com",
        screenshot: screenshot ? File.read(screenshot) : nil
      )

      # Capture handoff state
      puts "\nCapturing handoff state..."
      recording_service.capture_handoff_state(
        url: "https://activeagents.ai#newsletter",
        form_values: {
          email: "you@example.com"
        }
      )

      # Complete the recording
      recording_service.complete!

      puts "\n✅ Demo recording complete!"
      puts "   Recording ID: #{recording.id}"
      puts "   Actions: #{recording.reload.action_count}"
      puts "   Duration: #{recording.duration_ms}ms"
      puts "   Screenshots saved to: #{screenshots_dir}"

    rescue => e
      puts "\n❌ Recording failed: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      recording_service.fail!(e.message)
    end
  end

  desc "Seed the lander demo recording with mock data (for testing without Playwright)"
  task seed_demo: :environment do
    puts "Creating lander demo recording with mock data..."

    # Remove existing demo recording
    SessionRecording.where(name: "lander_demo").destroy_all

    # Create the demo recording
    recording = SessionRecording.create!(
      name: "lander_demo",
      status: :completed,
      duration_ms: 12000,
      action_count: 6,
      metadata: {
        started_at: Time.current.iso8601,
        completed_at: Time.current.iso8601,
        description: "Agent browsing Active Agent lander for newsletter signup",
        demo_type: "newsletter",
        handoff_state: {
          url: "https://activeagents.ai#newsletter",
          form_values: {
            email: ""
          },
          captured_at: Time.current.iso8601
        }
      }
    )

    # Create the action timeline - matches the newsletter demo flow
    actions = [
      {
        action_type: "navigate",
        sequence: 1,
        timestamp_ms: 0,
        value: "https://activeagents.ai",
        metadata: { url: "https://activeagents.ai" }
      },
      {
        action_type: "snapshot",
        sequence: 2,
        timestamp_ms: 1500,
        value: "initial_load",
        metadata: { snapshot_type: "full_page", description: "Initial page load - hero section visible" }
      },
      {
        action_type: "scroll",
        sequence: 3,
        timestamp_ms: 3500,
        value: "scroll_to_features",
        metadata: { scroll_position: { y: 400 }, description: "Scrolling down to features" }
      },
      {
        action_type: "scroll",
        sequence: 4,
        timestamp_ms: 5500,
        value: "scroll_to_newsletter",
        metadata: { scroll_position: { y: 800 }, description: "Scrolling to newsletter section" }
      },
      {
        action_type: "click",
        sequence: 5,
        timestamp_ms: 7500,
        selector: "#newsletter-email",
        value: "click_email",
        metadata: { element: "Email input field", description: "Clicking email input" }
      },
      {
        action_type: "type",
        sequence: 6,
        timestamp_ms: 9500,
        selector: "#newsletter-email",
        value: "you@example.com",
        metadata: { field: "email", description: "Typing email address" }
      }
    ]

    actions.each do |action_data|
      recording.recording_actions.create!(action_data)
    end

    puts "✅ Created demo recording with #{recording.action_count} actions"
    puts "   Recording ID: #{recording.id}"
    puts "   Recording name: #{recording.name}"
    puts "   Handoff available: #{recording.metadata['handoff_state'].present?}"
  end

  desc "Show demo recording details"
  task show_demo: :environment do
    recording = SessionRecording.find_by(name: "lander_demo")

    if recording
      puts "Demo Recording Details:"
      puts "  ID: #{recording.id}"
      puts "  Name: #{recording.name}"
      puts "  Status: #{recording.status}"
      puts "  Duration: #{recording.duration_ms}ms"
      puts "  Actions: #{recording.action_count}"
      puts "  Demo Type: #{recording.metadata['demo_type']}"
      puts "\nTimeline:"
      recording.recording_actions.order(:sequence).each do |action|
        puts "  #{action.sequence}. [#{action.timestamp_ms}ms] #{action.action_type}"
        puts "     Selector: #{action.selector}" if action.selector
        puts "     Value: #{action.value.to_s.truncate(50)}" if action.value
        puts "     Description: #{action.metadata['description']}" if action.metadata["description"]
      end
      puts "\nHandoff State: #{recording.metadata['handoff_state'].present? ? 'Available' : 'Not available'}"
      if recording.metadata["handoff_state"]
        puts "  URL: #{recording.metadata.dig('handoff_state', 'url')}"
      end
    else
      puts "No demo recording found. Run: bin/rails session_replay:seed_demo"
    end
  end
end

# frozen_string_literal: true

namespace :session_replay do
  desc "Seed the lander demo recording"
  task seed_demo: :environment do
    puts "Creating lander demo recording..."

    # Remove existing demo recording
    SessionRecording.where(name: "lander_demo").destroy_all

    # Create the demo recording
    recording = SessionRecording.create!(
      name: "lander_demo",
      status: :completed,
      duration_ms: 8500,
      action_count: 7,
      metadata: {
        started_at: Time.current.iso8601,
        completed_at: Time.current.iso8601,
        description: "Checkout flow demo for landing page",
        handoff_state: {
          url: "https://checkout.stripe.com/pay/cs_test_demo",
          form_values: {
            card: "4242 4242 4242 4242",
            expiry: "12/25",
            cvc: ""
          },
          captured_at: Time.current.iso8601
        }
      }
    )

    # Create the action timeline
    actions = [
      {
        action_type: "navigate",
        sequence: 1,
        timestamp_ms: 0,
        value: "https://checkout.stripe.com/pay/cs_test_demo",
        metadata: { url: "https://checkout.stripe.com/pay/cs_test_demo" }
      },
      {
        action_type: "snapshot",
        sequence: 2,
        timestamp_ms: 500,
        value: "initial_load",
        metadata: { snapshot_type: "full_page", description: "Initial page load" }
      },
      {
        action_type: "type",
        sequence: 3,
        timestamp_ms: 1500,
        selector: "#card-input",
        value: "4242 4242 4242 4242",
        metadata: { field: "card_number", element: "Card number input" }
      },
      {
        action_type: "type",
        sequence: 4,
        timestamp_ms: 4000,
        selector: "#expiry-input",
        value: "12/25",
        metadata: { field: "expiry", element: "Expiry date input" }
      },
      {
        action_type: "type",
        sequence: 5,
        timestamp_ms: 5500,
        selector: "#cvc-input",
        value: "123",
        metadata: { field: "cvc", element: "CVC input" }
      },
      {
        action_type: "click",
        sequence: 6,
        timestamp_ms: 7000,
        selector: "#pay-btn",
        value: "Pay $99.00",
        metadata: { element: "Pay button", button: "left" }
      },
      {
        action_type: "snapshot",
        sequence: 7,
        timestamp_ms: 8500,
        value: "payment_complete",
        metadata: { snapshot_type: "full_page", description: "Payment successful" }
      }
    ]

    actions.each do |action_data|
      recording.recording_actions.create!(action_data)
    end

    puts "Created demo recording with #{recording.action_count} actions"
    puts "Recording ID: #{recording.id}"
    puts "Recording name: #{recording.name}"
    puts "Handoff available: #{recording.metadata['handoff_state'].present?}"
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
      puts "\nTimeline:"
      recording.recording_actions.ordered.each do |action|
        puts "  #{action.sequence}. [#{action.timestamp_ms}ms] #{action.action_type}"
        puts "     Selector: #{action.selector}" if action.selector
        puts "     Value: #{action.value}" if action.value
      end
      puts "\nHandoff State: #{recording.metadata['handoff_state'].present? ? 'Available' : 'Not available'}"
    else
      puts "No demo recording found. Run: bin/rails session_replay:seed_demo"
    end
  end
end

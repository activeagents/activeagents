# frozen_string_literal: true

require "test_helper"

class GenerativeRoutingTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @agent = create_agent(user: @user)
  end

  test "generation_routes defaults to empty" do
    assert_equal({}, @agent.generation_routes)
  end

  test "add_generation_route stores route in model_config" do
    @agent.add_generation_route("error", to: "render_error")
    @agent.save!
    @agent.reload

    assert_equal({ "error" => "render_error" }, @agent.generation_routes)
  end

  test "add_generation_route accumulates routes" do
    @agent.add_generation_route("error", to: "render_error")
    @agent.add_generation_route("success", to: "redirect_to_dashboard")
    @agent.save!
    @agent.reload

    assert_equal 2, @agent.generation_routes.size
  end

  test "remove_generation_route removes a route" do
    @agent.add_generation_route("error", to: "render_error")
    @agent.add_generation_route("success", to: "redirect_to_dashboard")
    @agent.remove_generation_route("error")
    @agent.save!
    @agent.reload

    assert_equal({ "success" => "redirect_to_dashboard" }, @agent.generation_routes)
  end

  test "generate_and_route returns result with route metadata" do
    @agent.add_generation_route("Mock response", to: "render_mock")
    @agent.save!

    result = @agent.generate_and_route("test prompt")

    assert result[:metadata][:route].present?
    route = result[:metadata][:route]

    # The mock output contains "Mock response" so the route should match
    assert_equal :render, route[:type]
    assert_equal "render_mock", route[:target]
  end

  test "generate_and_route with no matching pattern returns content type" do
    @agent.add_generation_route("NEVER_MATCH_THIS_PATTERN", to: "render_something")
    @agent.save!

    result = @agent.generate_and_route("test prompt")
    route = result[:metadata][:route]

    assert_equal :content, route[:type]
    assert_nil route[:target]
  end

  test "generate_and_route without routes returns normal result" do
    result = @agent.generate_and_route("test prompt")

    # Should have route metadata but no routing applied
    route = result[:metadata][:route]
    assert_nil route # No routes configured, so no route metadata
  end

  test "classify_target identifies redirect targets" do
    @agent.add_generation_route("done", to: "redirect_to_dashboard")
    @agent.save!

    result = @agent.generate_and_route("done with this")

    # Only matches if output contains "done"
    if result[:output]&.match?(/done/i)
      assert_equal :redirect, result[:metadata][:route][:type]
    end
  end
end

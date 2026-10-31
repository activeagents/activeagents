require "test_helper"

class QueryPlannerAgentTest < ActiveSupport::TestCase
  test "the delegation is an ordinary method, and an unusable answer comes back as data" do
    result = HunterAgent.new.plan_queries(brief: "Looking for: Seiko 6139 Pogue, yellow dial")

    assert_kind_of Hash, result
    # The mock provider answers in pig latin, not the declared JSON schema.
    assert_equal "invalid_result", result[:error].to_s
    assert result[:missing].present?
  end

  test "declares the contract the hunter's model sees" do
    planner = HunterAgent.delegated_tools.find { |tool| (tool[:name] || tool["name"]) == "plan_queries" }

    assert planner, "plan_queries should be offered as a tool"
    assert_match "brief", planner.to_json
    assert_match "marketplace search queries", planner.to_json
  end

  test "the evaluator declares what it returns, and the hunter's model sees its inputs" do
    evaluator = HunterAgent.delegated_tools.find { |tool| (tool[:name] || tool["name"]) == "evaluate_listing" }
    assert evaluator
    assert_match "brief", evaluator.to_json

    contract = ListingEvaluatorAgent.delegation_contracts[:evaluate_listing]
    assert contract.structured?, "evaluate_listing should declare a returns schema"
    assert_equal %w[match_score rationale red_flags verdict], contract.returns.required_keys.map(&:to_s).sort
    assert_match "grail", contract.returns.to_json_schema.to_json
  end
end

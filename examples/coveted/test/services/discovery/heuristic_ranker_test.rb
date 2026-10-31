require "test_helper"

class Discovery::HeuristicRankerTest < ActiveSupport::TestCase
  setup do
    @hunt = create_hunt(create_user)
    @ranker = Discovery::HeuristicRanker.new(@hunt)
  end

  test "the item, in size and budget, is a grail" do
    scored = @ranker.score(listing(title: "Patagonia Synchilla Snap-T Pullover Fleece, 90s, Made in USA, Men's M", price_cents: 12_800, size: "M"))

    assert scored[:match_score] >= 85, scored.inspect
    assert_equal "grail", scored[:verdict]
    assert_match "brand matches", scored[:rationale]
    assert_empty scored[:red_flags].reject { |flag| flag.include?("condition") }
  end

  test "over budget and the wrong size cost points and are flagged" do
    scored = @ranker.score(listing(title: "Patagonia Synchilla Snap-T fleece 90s", price_cents: 30_000, size: "L"))

    assert scored[:match_score] < 65
    assert scored[:red_flags].any? { |flag| flag.include?("over budget") }
    assert scored[:red_flags].any? { |flag| flag.include?("size L") }
  end

  test "a different item, or a replica, is a pass" do
    scored = @ranker.score(listing(title: "Leica M6 style display body (replica)", brand: "Leica", price_cents: 12_000, description: "Decorative replica"))

    assert scored[:match_score] < 40
    assert_equal "pass", scored[:verdict]
    assert scored[:red_flags].any? { |flag| flag.include?("replica") }
  end

  private

  def listing(**attrs)
    ProductSearch::Listing.new({ brand: "Patagonia", condition: "used", url: "https://listings.example.com/x", currency: "USD" }.merge(attrs))
  end
end

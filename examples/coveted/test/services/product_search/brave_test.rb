require "test_helper"

class ProductSearch::BraveTest < ActiveSupport::TestCase
  test "maps web results to listings, reading prices out of snippets" do
    stub_request(:get, "https://api.search.brave.com/res/v1/web/search")
      .with(query: hash_including("q" => "Seiko 6139 Pogue"), headers: { "X-Subscription-Token" => "brave-key" })
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        web: { results: [
          { title: "Seiko 6139-6002 Pogue 1972", url: "https://www.chrono24.com/seiko/1.htm",
            description: "Serviced yellow dial Pogue, $1,150 shipped", thumbnail: { src: "https://img.example/p.jpg" }, page_age: "2026-10-28" },
          { title: "What is a Pogue?", url: "https://blog.example.com/pogue", description: "A history of the 6139." }
        ] }
      }.to_json)

    results = ProductSearch::Backends::Brave.new(api_key: "brave-key").search("Seiko 6139 Pogue")

    assert_equal 2, results.size
    watch = results.first
    assert_equal "chrono24", watch.source
    assert_equal 115_000, watch.price_cents
    assert_equal "USD", watch.currency
    assert_equal "https://img.example/p.jpg", watch.image_url
    assert_nil results.last.price_cents
  end
end

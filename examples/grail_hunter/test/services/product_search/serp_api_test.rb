require "test_helper"

class ProductSearch::SerpApiTest < ActiveSupport::TestCase
  setup do
    @backend = ProductSearch::Backends::SerpApi.new(api_key: "test-key")
  end

  test "maps Google Shopping results to listings" do
    stub_request(:get, "https://serpapi.com/search.json")
      .with(query: hash_including("engine" => "google_shopping", "q" => "Leica M6", "api_key" => "test-key"))
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        shopping_results: [
          { title: "Leica M6 Classic black", product_link: "https://www.ebay.com/itm/1", price: "$3,200.00",
            extracted_price: 3200.0, source: "eBay", thumbnail: "https://img.example/1.jpg", second_hand_condition: "used" },
          { title: "Leica M6 strap", link: "https://www.etsy.com/listing/2", price: "$40.00", extracted_price: 40.0, source: "Etsy" },
          { title: "no link, dropped", price: "$1.00" }
        ]
      }.to_json)

    results = @backend.search("Leica M6")

    assert_equal 2, results.size
    camera = results.first
    assert_equal "https://www.ebay.com/itm/1", camera.url
    assert_equal 320_000, camera.price_cents
    assert_equal "USD", camera.currency
    assert_equal "ebay", camera.source
    assert_equal "used", camera.condition
    assert_equal "https://img.example/1.jpg", camera.image_url

    assert_equal [ "Leica M6 strap" ], @backend.search("Leica M6", max_price_cents: 10_000).map(&:title)
  end

  test "fails loudly without a key or on an HTTP error" do
    assert_raises(ProductSearch::Error) { ProductSearch::Backends::SerpApi.new(api_key: nil).search("x") }

    stub_request(:get, /serpapi\.com/).to_return(status: 500, body: "boom")
    error = assert_raises(ProductSearch::Error) { @backend.search("x") }
    assert_match "HTTP 500", error.message
  end
end

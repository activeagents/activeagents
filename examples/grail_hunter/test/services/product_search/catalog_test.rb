require "test_helper"

class ProductSearch::CatalogTest < ActiveSupport::TestCase
  setup do
    @backend = ProductSearch::Backends::Catalog.new
  end

  test "ranks listings by how much of the query they match" do
    results = @backend.search("Patagonia Synchilla Snap-T 90s")

    assert results.size > 1
    assert_match "Synchilla Snap-T", results.first.title
    assert results.first.price_cents.positive?
    assert results.all? { |listing| listing.url.start_with?("https://") }
    assert results.map(&:url).uniq.size == results.size
  end

  test "respects a budget and a limit" do
    results = @backend.search("Patagonia", max_price_cents: 10_000, limit: 2)

    assert_equal 2, results.size
    assert results.all? { |listing| listing.price_cents <= 10_000 }
  end

  test "answers nothing for a query with no usable terms" do
    assert_empty @backend.search("the of")
    assert_empty @backend.search("")
  end

  test "fetches one listing by url" do
    listing = @backend.search("Leica M6 Classic").first
    assert_equal listing, @backend.fetch(listing.url)
    assert_nil @backend.fetch("https://listings.example.com/nowhere")
  end

  test "ProductSearch picks the catalog when no search key is set" do
    ProductSearch.reset!
    assert_equal "catalog", ProductSearch.backend_name
    assert_kind_of ProductSearch::Backends::Catalog, ProductSearch.backend
    assert ProductSearch.search("Seiko 6139 Pogue").any?
  end
end

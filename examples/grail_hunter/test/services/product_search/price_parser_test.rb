require "test_helper"

class ProductSearch::PriceParserTest < ActiveSupport::TestCase
  test "parses symbols, codes and thousands separators" do
    assert_equal [ 125_000, "USD" ], ProductSearch::PriceParser.parse("Leica M6 $1,250.00 shipped")
    assert_equal [ 30_000, "EUR" ], ProductSearch::PriceParser.parse("€300")
    assert_equal [ 4_500, "GBP" ], ProductSearch::PriceParser.parse("45 GBP buy it now")
    assert_equal [ 9_999, "USD" ], ProductSearch::PriceParser.parse("USD 99.99")
    assert_nil ProductSearch::PriceParser.parse("no price listed")
    assert_nil ProductSearch::PriceParser.parse(nil)
  end

  test "names the marketplace from a URL" do
    assert_equal "grailed", ProductSearch::PriceParser.source_from_url("https://www.grailed.com/listings/1")
    assert_equal "ebay", ProductSearch::PriceParser.source_from_url("https://ebay.co.uk/itm/2")
    assert_nil ProductSearch::PriceParser.source_from_url("not a url")
  end
end

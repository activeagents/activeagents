# Scores one listing against a brief. A delegation: HunterAgent offers it to
# its model as the evaluate_listing tool, and the declared `returns` schema
# becomes this agent's response format, so the caller gets data back rather
# than prose to re-parse.
class ListingEvaluatorAgent < ApplicationAgent
  delegation :evaluate_listing,
             description: "Score one marketplace listing against the collector's brief, like a dealer " \
                          "looking over a lot. Returns a 0-100 match score, a verdict, a short rationale " \
                          "and red flags (replica, wrong size, stock photos, suspicious price)." do
    string :brief, required: true, description: "The collector's brief: item, brand, sizes, budget, condition"
    string :title, required: true, description: "Listing title"
    string :url, required: true, description: "Listing URL"
    string :price, description: "Listing price with currency, e.g. '245 USD'"
    string :condition, description: "Condition as listed"
    string :size, description: "Size as listed"
    string :source, description: "Marketplace the listing is on"
    string :description, description: "Listing description or search snippet"

    returns do
      integer :match_score, required: true, description: "0-100"
      string :verdict, required: true, enum: Finding::VERDICTS
      string :rationale, required: true, description: "Two or three sentences for the collector"
      array :red_flags, of: :string, required: true, description: "Empty when nothing argues against it"
    end
  end

  def evaluate_listing(brief:, title:, url:, price: nil, condition: nil, size: nil, source: nil, description: nil)
    @brief = brief
    @listing = { title:, url:, price:, condition:, size:, source:, description: }.compact

    prompt
  end
end

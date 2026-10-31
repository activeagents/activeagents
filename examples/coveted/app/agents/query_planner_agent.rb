# Turns a brief into marketplace search queries. A delegation HunterAgent
# can call when the brief is vague, and what the "Plan queries" button on a
# hunt runs (Hunt#plan!) to seed the run's first searches.
class QueryPlannerAgent < ApplicationAgent
  delegation :plan_queries,
             description: "Turn a collector's brief into marketplace search queries: exact model names, " \
                          "eras, colourways, common abbreviations and misspellings, plus which " \
                          "marketplaces to try. Call it once, at the start, when the brief is vague." do
    string :brief, required: true, description: "The collector's brief"

    returns do
      array :queries, of: :string, required: true, description: "Three to six search queries, most specific first"
      array :negative_keywords, of: :string, required: true, description: "Words that mark the wrong item: replica, kids, reissue"
      array :sources, of: :string, required: true, description: "Marketplaces worth searching, e.g. grailed, ebay, depop, etsy, chrono24, reverb, discogs"
      string :notes, required: true, description: "One or two sentences on what distinguishes the real thing"
    end
  end

  def plan_queries(brief:)
    @brief = brief

    prompt
  end
end

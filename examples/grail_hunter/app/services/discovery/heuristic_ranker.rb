module Discovery
  # Scores a listing against a hunt without a model. The pipeline uses it
  # for candidates the agent did not record, which is every candidate when
  # the provider cannot call tools (the mock). Keyword overlap, brand, budget,
  # size and condition, with the reasons spelled out so the finding's
  # rationale is honest about how it was scored.
  class HeuristicRanker
    STOPWORDS = %w[the a an of in for and with or to from on at by].freeze

    def initialize(hunt)
      @hunt = hunt
      @terms = tokenize([ hunt.title, hunt.keywords, hunt.brand ].join(" "))
      @brand_terms = tokenize(hunt.brand)
    end

    # @return [Hash] match_score, verdict, rationale, red_flags
    def score(listing)
      words = tokenize([ listing.title, listing.brand, listing.description ].join(" "))
      reasons = []
      flags = []

      overlap = @terms & words
      coverage = @terms.empty? ? 0.0 : overlap.size.to_f / @terms.size
      score = (coverage * 60).round
      reasons << "matches #{overlap.size} of #{@terms.size} brief terms (#{overlap.first(5).join(', ')})" if overlap.any?

      if @brand_terms.any?
        if (@brand_terms - words).empty?
          score += 20
          reasons << "brand matches"
        else
          score -= 15
          flags << "brand not in listing"
        end
      end

      if @hunt.max_price_cents && listing.price_cents
        if listing.price_cents <= @hunt.max_price_cents
          score += 10
          reasons << "within budget"
        else
          over = ((listing.price_cents - @hunt.max_price_cents) * 100.0 / @hunt.max_price_cents).round
          score -= over > 50 ? 30 : 12
          flags << "#{over}% over budget"
        end
      end

      sizes = @hunt.size_list.map { |size| size.to_s.downcase }
      if sizes.any? && listing.size.present?
        if sizes.include?(listing.size.to_s.downcase)
          score += 10
          reasons << "size #{listing.size} fits"
        else
          score -= 20
          flags << "size #{listing.size} is not one of #{@hunt.size_list.join('/')}"
        end
      end

      if @hunt.condition != "any" && listing.condition.present? && listing.condition != @hunt.condition
        score -= 5
        flags << "condition is #{listing.condition}, asked for #{@hunt.condition}"
      end

      if words.intersect?(%w[replica reproduction inspired dummy fake style])
        score -= 40
        flags << "listing reads like a replica or lookalike"
      end

      # The brand alone is not a find: a brand's shorts are not its fleece.
      if (overlap - @brand_terms).empty?
        score = [ score, 35 ].min
        flags << "only the brand matches the brief"
      end

      score = score.clamp(0, 100)
      {
        match_score: score,
        verdict: verdict_for(score),
        rationale: "Heuristic match (no model scored this): #{reasons.presence&.join(', ') || 'few brief terms matched'}.",
        red_flags: flags
      }
    end

    private

    def verdict_for(score)
      case score
      when 85.. then "grail"
      when 65...85 then "strong"
      when 40...65 then "maybe"
      else "pass"
      end
    end

    def tokenize(text)
      text.to_s.downcase.scan(/[a-z0-9][a-z0-9'\-]*/).map { |word| word.delete("'") }
          .reject { |word| word.size < 2 || STOPWORDS.include?(word) }.uniq
    end
  end
end

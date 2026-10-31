module Discovery
  # Writes a finding for a run, once per listing URL per hunt. The agent's
  # record_finding tool and the heuristic backfill both come through here,
  # so the dedupe rule and the column allowlist live in one place.
  module FindingRecorder
    ATTRIBUTES = %i[
      title url source price_cents currency condition size image_url description
      match_score verdict rationale red_flags listed_at
    ].freeze

    module_function

    # @return [Array(Finding, Boolean)] the finding, and whether it was created
    def record(run, attrs, scored_by:)
      attrs = attrs.to_h.symbolize_keys.slice(*ATTRIBUTES)
      hunt = run.hunt
      url = attrs[:url].to_s.strip

      if (existing = hunt.findings.find_by(url: url))
        # An agent's judgement replaces a heuristic one; nothing else moves.
        if scored_by == "agent" && !existing.scored_by_agent?
          existing.update!(attrs.slice(:match_score, :verdict, :rationale, :red_flags).merge(scored_by: "agent", discovery_run: run))
        end
        return [ existing, false ]
      end

      finding = hunt.findings.create!(
        attrs.merge(
          url: url,
          user: hunt.user,
          discovery_run: run,
          scored_by: scored_by,
          currency: attrs[:currency].presence || hunt.currency,
          red_flags: Array(attrs[:red_flags]).map(&:to_s)
        )
      )
      [ finding, true ]
    end
  end
end

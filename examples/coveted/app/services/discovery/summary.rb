module Discovery
  # A plain summary of a check written from its results. Used when the
  # provider gave no summary of its own: the mock provider never does, and a
  # real model's final answer may not be the JSON it was asked for. Reads
  # like something a person would say, so the collector is never shown
  # provider output that was never meant for them.
  module Summary
    module_function

    def for(run)
      findings = run.findings.by_score.to_a
      looked_at = run.candidate_count
      return "We looked at #{pluralize(looked_at, 'listing')} and none fit your brief well enough to show you. We'll keep checking." if findings.empty?

      best = findings.first
      sentences = []
      sentences << "We looked at #{pluralize(looked_at, 'listing')} and kept #{findings.size == 1 ? 'one' : findings.size}."
      sentences << "The best is #{best.title.truncate(80)}#{price_phrase(best)}, which looks like #{best.verdict_label.downcase == 'exactly it' ? 'exactly what you asked for' : best.verdict_label.downcase.sub('a ', '')}."

      rest = findings.drop(1).group_by(&:verdict).map { |verdict, group| "#{pluralize(group.size, Finding::VERDICT_LABELS.fetch(verdict.to_s, 'other').downcase.sub('exactly it', 'exact match'))}" }
      sentences << "Also: #{rest.to_sentence}." if rest.any?

      flags = findings.flat_map(&:red_flag_list)
      sentences << "Watch out: #{flags.uniq.first(3).to_sentence}." if flags.any?
      sentences.join(" ")
    end

    def price_phrase(finding)
      return "" unless finding.price_cents

      amount = finding.price_cents / 100.0
      amount = amount % 1 == 0 ? amount.to_i : amount
      " at #{amount} #{finding.currency || 'USD'}#{finding.source.present? ? " on #{finding.source.to_s.capitalize}" : ''}"
    end

    def pluralize(count, noun)
      "#{count} #{count == 1 ? noun : noun.pluralize}"
    end
  end
end

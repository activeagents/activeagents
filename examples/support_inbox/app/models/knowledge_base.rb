# A deliberately tiny retrieval layer: articles live in
# config/knowledge_base.yml and matching is keyword overlap. Enough to
# demonstrate grounded replies (and to show up in traces as longer
# prompts) without pulling in a vector store.
class KnowledgeBase
  ARTICLES_PATH = Rails.root.join("config/knowledge_base.yml")

  class << self
    def articles
      @articles ||= YAML.load_file(ARTICLES_PATH)
    end

    # Top articles sharing the most keywords with the ticket text.
    def relevant_to(ticket, limit: 2)
      ticket_words = tokenize("#{ticket.subject} #{ticket.body}")

      scored = articles.map do |article|
        keywords = article.fetch("keywords", [])
        score = (keywords & ticket_words).size
        [ score, article ]
      end

      scored.select { |score, _| score.positive? }
            .sort_by { |score, _| -score }
            .first(limit)
            .map(&:last)
    end

    private

    def tokenize(text)
      text.downcase.scan(/[a-z][a-z-]+/).uniq
    end
  end
end

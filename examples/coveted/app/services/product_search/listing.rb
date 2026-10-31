module ProductSearch
  # One marketplace listing, whichever backend found it.
  Listing = Struct.new(
    :title, :url, :source, :price_cents, :currency, :condition, :size, :brand,
    :image_url, :description, :listed_at,
    keyword_init: true
  ) do
    def price
      price_cents && price_cents / 100.0
    end

    def price_label
      return nil unless price_cents

      amount = price % 1 == 0 ? price.to_i : format("%.2f", price)
      "#{amount} #{currency || 'USD'}"
    end

    # The hash a tool returns to the model: compact, strings only.
    def tool_payload
      {
        title: title,
        url: url,
        source: source,
        price: price_label,
        condition: condition,
        size: size,
        brand: brand,
        image_url: image_url,
        description: description&.to_s&.truncate(400),
        listed_at: listed_at&.to_s
      }.compact
    end

    # One line in the candidate list the agent reads.
    def to_prompt_line
      meta = [ price_label, source, condition, size && "size #{size}" ].compact.join(" | ")
      line = "#{title} (#{meta}) #{url}"
      line += "\n   #{description.to_s.squish.truncate(220)}" if description.present?
      line
    end
  end
end

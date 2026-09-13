# frozen_string_literal: true

require "cgi"

module ActionMailAgent
  # Reduces an email body to what the person actually wrote this time.
  #
  # A reply carries the whole thread with it: the new sentence on top, then the
  # client's quote of everything before it, then a signature, then a corporate
  # disclaimer. Handing all of that to a model wastes the context window and
  # invites it to answer a question that was already answered two replies ago.
  #
  #   parsed = ActionMailAgent::BodyParser.new(mail).call
  #   parsed.visible  # => "Any update on this?"
  #   parsed.quoted   # => "On Mon, Sep 1, 2025 at 9:03 AM Support wrote:\n> ..."
  #
  # The quoted text is kept rather than discarded: it is what a human reading
  # the conversation later needs, and what tells you the parser cut in the
  # wrong place.
  class BodyParser
    Result = Struct.new(:visible, :quoted, keyword_init: true) do
      def blank?
        visible.blank?
      end
    end

    # "On Tue, 3 Jun 2025 at 14:02, Ada <ada@example.com> wrote:", and the
    # same sentence in the languages whose clients spell it differently.
    ATTRIBUTION_LINE = /\A\s*(On|Am|Le|El|Op|Den)\b.{0,300}?\b(wrote|schrieb|a écrit|escribió|skrev|schreef):\s*\z/i

    # An attribution long enough to wrap. Gmail breaks after the comma; the
    # line that follows carries the verb.
    ATTRIBUTION_OPENING = /\A\s*(On|Am|Le|El|Op|Den)\b.{0,300}\z/i
    ATTRIBUTION_CLOSING = /\b(wrote|schrieb|a écrit|escribió|skrev|schreef):\s*\z/i

    # Outlook and the forwarding convention every client agrees on.
    SEPARATOR_LINE = /\A\s*[-_*]{2,}\s*(Original Message|Original Nachricht|Ursprüngliche Nachricht|Forwarded message|Message d'origine|Mensaje original)\s*[-_*]{2,}\s*\z/i
    DIVIDER_LINE = /\A\s*_{10,}\s*\z/
    HEADER_LINE = /\A\s*(From|Sent|To|Cc|Subject|Date|Von|Gesendet|De|Enviado):\s*\S/i
    QUOTE_LINE = /\A\s*>/

    # RFC 3676 §4.3: a line of exactly "-- " opens the signature. Clients drop
    # the trailing space often enough that it has to be optional.
    SIGNATURE_LINE = /\A\s*--\s*\z/
    MOBILE_SIGNATURE_LINE = /\A\s*(Sent from my \S+|Get Outlook for \S+|Sent via \S+)/i

    # @param mail [Mail::Message]
    # @param delimiter [String, nil] an explicit "reply above this line" marker
    def initialize(mail, delimiter: ActionMailAgent.reply_delimiter)
      @mail = mail
      @delimiter = delimiter.presence
    end

    # @return [Result]
    def call
      text = normalize(source_text)
      visible, quoted = split(text)

      Result.new(visible: visible.strip, quoted: quoted.strip)
    end

    private

    attr_reader :mail, :delimiter

    # The text/plain part, falling back to a flattened text/html one. An
    # HTML-only sender is the common case, not the exotic one.
    def source_text
      if (part = text_part)
        decode(part)
      elsif (part = html_part)
        html_to_text(decode(part))
      elsif mail.respond_to?(:multipart?) && mail.multipart?
        ""
      else
        body = decode(mail)
        mail.mime_type == "text/html" ? html_to_text(body) : body
      end
    end

    def text_part
      mail.respond_to?(:text_part) ? mail.text_part : nil
    end

    def html_part
      mail.respond_to?(:html_part) ? mail.html_part : nil
    end

    # Mail raises on charsets it cannot resolve, and mislabelled encodings are
    # routine in inbound mail. A body that cannot be decoded is still worth
    # reading in the raw.
    def decode(part)
      part.decoded.to_s
    rescue StandardError
      part.body.raw_source.to_s
    rescue StandardError
      ""
    end

    def normalize(text)
      text
        .dup
        .force_encoding(Encoding::UTF_8)
        .scrub("")
        .gsub("\r\n", "\n")
        .gsub("\r", "\n")
        .gsub(" ", " ")
    end

    # Everything below the first quote boundary is history. Gmail wraps it in
    # a container of its own, which is a cleaner cut than anything the
    # flattened text offers, so it is taken first.
    def html_to_text(html)
      body = html.split(/<blockquote\b|<div[^>]*\b(?:gmail_quote|moz-cite-prefix|yahoo_quoted)\b/i).first.to_s

      body
        .gsub(%r{<(script|style)[^>]*>.*?</\1>}mi, "")
        .gsub(%r{<br\s*/?>}i, "\n")
        .gsub(%r{</(p|div|tr|li|h[1-6]|blockquote)>}i, "\n\n")
        .gsub(/<[^>]*>/, "")
        .then { |text| CGI.unescapeHTML(text) }
        .gsub(/[ \t]+\n/, "\n")
        .gsub(/\n{3,}/, "\n\n")
    end

    def split(text)
      lines = text.split("\n", -1)
      boundary = boundary_index(lines)

      return [ text, "" ] unless boundary

      [ lines[0...boundary].join("\n"), lines[boundary..].join("\n") ]
    end

    def boundary_index(lines)
      delimiter_index(lines) || quote_index(lines) || signature_index(lines)
    end

    def delimiter_index(lines)
      return nil unless delimiter

      lines.index { |line| line.include?(delimiter) }
    end

    def quote_index(lines)
      lines.each_with_index do |line, index|
        return index if line.match?(ATTRIBUTION_LINE)
        return index if line.match?(SEPARATOR_LINE)
        return index if wrapped_attribution?(lines, index)
        return index if outlook_header?(lines, index)
        return index if quote_block?(lines, index)
      end

      nil
    end

    # "On Tue, 3 Jun 2025 at 14:02, Ada Lovelace\n<ada@example.com> wrote:"
    def wrapped_attribution?(lines, index)
      return false unless lines[index].match?(ATTRIBUTION_OPENING)
      return false if lines[index].match?(ATTRIBUTION_CLOSING)

      lines[index + 1, 2].to_a.each_with_index.any? do |line, offset|
        # A blank line ends the sentence; an attribution never spans one.
        break false if line.blank? && offset.zero?

        line.match?(ATTRIBUTION_CLOSING)
      end
    end

    # Outlook's quote is a header block, sometimes under a row of underscores.
    # One "From:" line proves nothing — a sentence can start that way — so a
    # second header line has to follow it.
    def outlook_header?(lines, index)
      line = lines[index]
      return false unless line.match?(HEADER_LINE) || line.match?(DIVIDER_LINE)

      following = lines[index + 1, 4].to_a.reject(&:blank?)

      if line.match?(DIVIDER_LINE)
        following.first.to_s.match?(HEADER_LINE)
      else
        following.any? { |candidate| candidate.match?(HEADER_LINE) }
      end
    end

    # A ">" block counts as the boundary only when the rest of the message is
    # quoted. Someone quoting one line mid-message and then carrying on is
    # writing, not replying above a thread.
    def quote_block?(lines, index)
      return false unless lines[index].match?(QUOTE_LINE)

      lines[index..].none? { |line| line.present? && !line.match?(QUOTE_LINE) && !line.match?(ATTRIBUTION_LINE) }
    end

    def signature_index(lines)
      lines.each_with_index do |line, index|
        next if index.zero?
        return index if line.match?(SIGNATURE_LINE)
        return index if line.match?(MOBILE_SIGNATURE_LINE)
      end

      nil
    end
  end
end

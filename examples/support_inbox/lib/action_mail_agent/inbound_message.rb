# frozen_string_literal: true

module ActionMailAgent
  # One normalized view of an inbound email: who wrote, what they wrote this
  # time (see BodyParser), how it threads, and the header tells that say it was
  # sent by a machine.
  #
  # Everything downstream — the loop guard, the mailbox, the agent prompt —
  # reads this rather than poking at Mail::Message, so there is one place where
  # "the customer's address" or "the message they are replying to" is decided.
  class InboundMessage
    # Headers set by vacation responders, ticket systems and mail servers to
    # say "a machine sent this". RFC 3834 standardized the first one; the rest
    # are what the field actually uses.
    AUTO_SUBMITTED = "Auto-Submitted"
    AUTO_RESPONSE_SUPPRESS = "X-Auto-Response-Suppress"
    BULK_PRECEDENCES = %w[bulk junk list auto_reply].freeze
    LIST_HEADERS = %w[List-Id List-Unsubscribe List-Post].freeze
    BOUNCE_SUBJECTS = /\A\s*(undeliverable|delivery status notification|mail delivery (failed|subsystem)|returned mail|automatic reply|out of office|auto(matic)?[ -]?reply)/i

    # Recipient headers a forwarder adds. The address a message was delivered
    # to is often not in To: at all — a forwarded support alias is the normal
    # case, not the exception — and the +tag that threads a conversation rides
    # on whichever one survived.
    DELIVERY_HEADERS = %w[Delivered-To X-Original-To X-Forwarded-To Envelope-To X-Envelope-To].freeze

    attr_reader :mail, :inbound_email

    # @param mail [Mail::Message]
    # @param inbound_email [ActionMailbox::InboundEmail, nil]
    def initialize(mail, inbound_email: nil)
      @mail = mail
      @inbound_email = inbound_email
    end

    def from
      @from ||= Addressing.normalize(Array(mail.from).first)
    end

    # The display name, when the client sent one: "Dana Scully" out of
    # "Dana Scully <dana@example.com>".
    def from_name
      @from_name ||= begin
        address = mail[:from]&.address_list&.addresses&.first
        name = address&.display_name.presence || address&.name.presence
        name.to_s.strip.presence
      rescue StandardError
        nil
      end
    end

    def subject
      @subject ||= mail.subject.to_s.strip
    end

    # The subject with any number of Re:/Fwd: prefixes removed, which is what a
    # conversation should be titled after.
    def bare_subject
      @bare_subject ||= subject.sub(/\A((re|aw|r|fwd?|vs|sv|antw)\s*(\[\d+\])?\s*:\s*)+/i, "").strip
    end

    def message_id
      @message_id ||= unbracket(mail.message_id)
    end

    # Message-Ids this email claims to answer, newest first: In-Reply-To, then
    # the References chain. Threading walks these in order, so a reply to a
    # reply lands on the conversation even when the +tag was stripped.
    def reference_ids
      @reference_ids ||= begin
        ids = Array(mail.in_reply_to) + Array(mail.references)
        ids.map { |id| unbracket(id) }.compact_blank.uniq
      end
    end

    def recipients
      @recipients ||= begin
        headers = DELIVERY_HEADERS.flat_map { |name| header_values(name) }
        (Array(mail.to) + Array(mail.cc) + headers).map { |address| Addressing.normalize(address) }.compact_blank.uniq
      end
    end

    # The +tags on every recipient address — where a conversation token
    # travels.
    def tags
      @tags ||= Addressing.tags(recipients)
    end

    def parsed
      @parsed ||= BodyParser.new(mail).call
    end

    # What the person wrote this time, with the quoted thread and signature
    # taken off.
    def body
      parsed.visible
    end

    def quoted_body
      parsed.quoted
    end

    def attachments
      @attachments ||= Array(mail.attachments).map do |attachment|
        {
          filename: attachment.filename,
          content_type: attachment.mime_type,
          byte_size: attachment.body.decoded.bytesize
        }
      rescue StandardError
        { filename: attachment.filename, content_type: attachment.mime_type, byte_size: nil }
      end
    end

    def date
      mail.date&.to_time || Time.current
    rescue StandardError
      Time.current
    end

    # RFC 3834: anything but "no" means a machine sent it, and answering a
    # machine is how mail loops start.
    def auto_generated?
      value = header(AUTO_SUBMITTED)
      return true if value.present? && value.to_s.strip.downcase != "no"
      return true if header(AUTO_RESPONSE_SUPPRESS).present?
      return true if BULK_PRECEDENCES.include?(header("Precedence").to_s.strip.downcase)
      return true if header("X-Autoreply").present? || header("X-Autorespond").present?

      subject.match?(BOUNCE_SUBJECTS)
    end

    def mailing_list?
      LIST_HEADERS.any? { |name| header(name).present? }
    end

    # A null return-path is the envelope sender of a bounce; the report content
    # type and the failed-recipients header are the other two tells.
    def bounce?
      return true if header("Return-Path").to_s.strip.in?([ "<>", "" ]) && header("Return-Path").present?
      return true if header("X-Failed-Recipients").present?
      return true if mail.content_type.to_s.include?("report-type=delivery-status")

      from.start_with?("mailer-daemon@", "postmaster@")
    end

    def header(name)
      mail[name]&.to_s
    rescue StandardError
      nil
    end

    # A record of the exchange for the conversation log: enough to see what
    # arrived without re-parsing the raw source.
    def to_h
      {
        from: from,
        from_name: from_name,
        subject: subject,
        message_id: message_id,
        references: reference_ids,
        recipients: recipients,
        attachments: attachments,
        auto_generated: auto_generated?,
        mailing_list: mailing_list?,
        bounce: bounce?
      }
    end

    private

    def header_values(name)
      Array(mail[name]).flat_map { |field| field.to_s.split(",") }
    rescue StandardError
      []
    end

    def unbracket(value)
      value.to_s.strip.delete("<>").presence
    end
  end
end

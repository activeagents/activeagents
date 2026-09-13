# frozen_string_literal: true

module ActionMailAgent
  # The +tag half of threading: `support@example.com` becomes
  # `support+f3a9c1d8@example.com` on the way out, and the tag comes back on
  # the way in even from clients that strip every header they do not
  # understand.
  #
  # Headers are the first way a reply is threaded (see Exchange); this is the
  # one that survives a customer forwarding the mail to a colleague who replies
  # from a different client.
  module Addressing
    module_function

    # @param address [String] the address replies are sent from
    # @param token [String] the conversation's token
    # @param domain [String, nil] overrides the domain of +address+
    # @return [String] "support+<token>@example.com"
    def tagged(address, token, domain: ActionMailAgent.reply_to_domain)
      local, _, address_domain = normalize(address).rpartition("@")
      return address if local.blank? || token.blank?

      "#{local.split("+").first}+#{token}@#{domain.presence || address_domain}"
    end

    # The +tag of the first address carrying one.
    #
    # @param addresses [Array<String>, String, nil]
    # @return [String, nil]
    def tags(addresses)
      Array(addresses).filter_map do |address|
        local = normalize(address).split("@").first.to_s
        tag = local.split("+", 2)[1]
        tag.presence
      end
    end

    # Strips the +tag, so `support+f3a9@example.com` and `support@example.com`
    # compare equal.
    # @return [String]
    def untagged(address)
      local, _, domain = normalize(address).rpartition("@")
      return normalize(address) if local.blank?

      "#{local.split("+").first}@#{domain}"
    end

    # @return [String] downcased, whitespace- and bracket-free
    def normalize(address)
      address.to_s.strip.delete("<>").downcase
    end

    # Does +address+ match this list of addresses and patterns?
    # @param address [String]
    # @param patterns [Array<String, Regexp>]
    def match?(address, patterns)
      candidate = normalize(address)
      return false if candidate.blank?

      bare = untagged(candidate)

      Array(patterns).any? do |pattern|
        case pattern
        when Regexp then pattern.match?(candidate) || pattern.match?(bare)
        else normalize(pattern) == candidate || normalize(pattern) == bare
        end
      end
    end

    # @return [String, nil] the domain half of an address
    def domain(address)
      normalize(address).split("@").last.presence
    end

    # A conversation token, lowercase on purpose: the local part of an address
    # is case-sensitive per RFC 5321, and almost nothing treats it that way.
    # Mail servers, forwarders and a customer typing the address back in all
    # change case freely, and a token that does not survive that is a
    # conversation that silently starts a new ticket on every reply.
    def generate_token
      SecureRandom.hex(12)
    end
  end
end

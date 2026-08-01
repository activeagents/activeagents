# frozen_string_literal: true

# Approximates token counts for text the platform holds but never sent as
# its own billable unit — instructions, tool schemas, MCP schemas, memory
# blocks, individual messages — so ContextUtilization can attribute the
# overhead that every request re-sends.
#
# Deliberately NOT a tokenizer. No BPE vocabulary ships with the app and
# the correct vocabulary differs per provider, so exact per-message counts
# are not available from what is persisted today. Estimates are therefore
# only ever used to *attribute* a total that is measured
# (AgentGeneration#input_tokens); they never produce the headline number,
# and every segment derived from them is flagged `estimated: true`.
#
# The two ratios below are the practical middle of GPT and Claude BPEs:
# prose runs ~3.6 chars/token, while JSON is punctuation-dense and
# tokenizes noticeably worse.
class TokenEstimator
  PROSE_CHARS_PER_TOKEN = 3.6
  JSON_CHARS_PER_TOKEN = 2.8

  # Per-message envelope (role, delimiters, name fields) that providers add
  # on top of the content itself.
  MESSAGE_OVERHEAD_TOKENS = 4

  def self.for_text(text)
    return 0 if text.blank?

    (text.to_s.length / PROSE_CHARS_PER_TOKEN).ceil
  end

  # Structured payloads — tool schemas, MCP advertisements, tool arguments
  # and results — serialized the way a provider receives them.
  def self.for_json(value)
    return 0 if value.blank?

    serialized = value.is_a?(String) ? value : value.to_json
    (serialized.length / JSON_CHARS_PER_TOKEN).ceil
  rescue StandardError
    0
  end

  # One AgentMessage's footprint in the window. Tool messages carry both
  # the arguments the model emitted and the result that came back — both
  # occupy the window, and the split is what tells an operator whether to
  # trim the schema or truncate the result.
  #
  # @return [Array(Integer, Integer)] [inbound, outbound] tokens
  def self.for_message(message)
    case message.role
    when "tool"
      [
        for_json(message.tool_arguments) + MESSAGE_OVERHEAD_TOKENS,
        for_json(message.tool_result.presence || message.content)
      ]
    else
      [ 0, for_text(message.content) + MESSAGE_OVERHEAD_TOKENS ]
    end
  end
end

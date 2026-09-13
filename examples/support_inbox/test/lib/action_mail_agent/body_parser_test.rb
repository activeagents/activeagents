require "test_helper"

# What the customer wrote this time, separated from everything their client
# stapled underneath it. Every case here is a real client's quoting style —
# getting these wrong means the agent answers a question from three replies
# ago, or pays to re-read the whole thread on every turn.
class ActionMailAgent::BodyParserTest < ActiveSupport::TestCase
  test "a plain message is left alone" do
    parsed = parse("Is there a bulk CSV download?")

    assert_equal "Is there a bulk CSV download?", parsed.visible
    assert_equal "", parsed.quoted
  end

  test "a Gmail attribution line ends the message" do
    parsed = parse(<<~BODY)
      Perfect, thank you.

      On Mon, Sep 1, 2025 at 9:03 AM Support <support@example.com> wrote:
      > You can export everything from Settings.
    BODY

    assert_equal "Perfect, thank you.", parsed.visible
    assert_includes parsed.quoted, "You can export everything"
  end

  test "an attribution that wraps onto a second line still ends the message" do
    parsed = parse(<<~BODY)
      Still broken.

      On Tue, 3 Jun 2025 at 14:02, Ada Lovelace
      <ada@example.com> wrote:
      > Have you tried the reset link?
    BODY

    assert_equal "Still broken.", parsed.visible
  end

  test "an Outlook header block ends the message" do
    parsed = parse(<<~BODY)
      Any update?

      From: Support <support@example.com>
      Sent: Monday, September 1, 2025 9:03 AM
      To: Dana <dana@example.com>
      Subject: Re: Charged twice

      We are looking into it.
    BODY

    assert_equal "Any update?", parsed.visible
    assert_includes parsed.quoted, "We are looking into it."
  end

  test "a forwarded-message separator ends the message" do
    parsed = parse(<<~BODY)
      Sending this along.

      ---------- Forwarded message ----------
      From: Dana <dana@example.com>
    BODY

    assert_equal "Sending this along.", parsed.visible
  end

  test "a signature is cut, and a line that merely starts with two dashes is not" do
    parsed = parse(<<~BODY)
      Thanks!

      --
      Dana Scully
      FBI
    BODY

    assert_equal "Thanks!", parsed.visible
    assert_includes parsed.quoted, "Dana Scully"

    kept = parse("We use --force on the CLI and it fails.")
    assert_equal "We use --force on the CLI and it fails.", kept.visible
  end

  test "a mobile signature is cut" do
    assert_equal "On my way.", parse("On my way.\n\nSent from my iPhone").visible
  end

  test "a quote in the middle of a message is not a boundary" do
    body = <<~BODY
      You said:

      > the export runs nightly

      but it has not run since Friday. Can you check?
    BODY

    assert_includes parse(body).visible, "but it has not run since Friday"
  end

  test "the configured reply delimiter wins over everything else" do
    parsed = parse(<<~BODY)
      Confirmed, that worked.

      #{ActionMailAgent.reply_delimiter}
      Earlier reply from the agent, quoted by the client.
    BODY

    assert_equal "Confirmed, that worked.", parsed.visible
  end

  test "an HTML-only message is flattened and its quote removed" do
    mail = Mail.new(content_type: "text/html; charset=UTF-8", body: <<~HTML)
      <div>Perfect, thank you.<br><br></div>
      <div class="gmail_quote">
        <blockquote>You can export everything from Settings.</blockquote>
      </div>
    HTML

    assert_equal "Perfect, thank you.", ActionMailAgent::BodyParser.new(mail).call.visible
  end

  test "a multipart message prefers the text part" do
    mail = Mail.new do
      text_part { body "Plain text answer." }
      html_part { body "<p>HTML answer.</p>" }
    end

    assert_equal "Plain text answer.", ActionMailAgent::BodyParser.new(mail).call.visible
  end

  test "a body in a charset the headers lie about does not raise" do
    mail = Mail.new(charset: "utf-8", body: "caf\xE9 — broken bytes".dup.force_encoding("ASCII-8BIT"))

    assert_nothing_raised { ActionMailAgent::BodyParser.new(mail).call }
  end

  private

  def parse(body)
    ActionMailAgent::BodyParser.new(Mail.new(body: body)).call
  end
end

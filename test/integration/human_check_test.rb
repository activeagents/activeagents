# frozen_string_literal: true

require "test_helper"

# The public signup and newsletter forms refuse submissions that fail
# HumanCheck: a filled honeypot always, and a missing or invalid Cloudflare
# Turnstile token once TURNSTILE_SITE_KEY and TURNSTILE_SECRET_KEY are set.
class HumanCheckTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  SITEVERIFY = "https://challenges.cloudflare.com/turnstile/v0/siteverify"
  SITE_KEY = "1x00000000000000000000AA"
  SECRET_KEY = "1x0000000000000000000000000000000AA"

  test "a landing page signup with a filled honeypot creates nothing" do
    assert_no_difference [ "User.count", "Account.count", "Session.count" ] do
      assert_no_enqueued_jobs only: ActionMailer::MailDeliveryJob do
        post "/registration", params: { email_address: "person@example.com", website: "https://spam.example" }, as: :json
      end
    end
    assert_response :unprocessable_entity
    assert_equal RequiresHuman::MESSAGE, response.parsed_body["error"]
  end

  test "the full registration form with a filled honeypot re-renders with the message" do
    assert_no_difference "User.count" do
      post "/registration", params: {
        user: { email_address: "person@example.com", password: "password123", password_confirmation: "password123" },
        website: "https://spam.example"
      }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /confirm you're a person/
    assert_select "input[name=?]", "user[email_address]"
  end

  test "a newsletter subscription with a filled honeypot creates nothing" do
    assert_no_difference "NewsletterSubscription.count" do
      post "/newsletter_subscription", params: { email_address: "reader@example.com", website: "x" }, as: :json
    end
    assert_response :unprocessable_entity
    assert_equal RequiresHuman::MESSAGE, response.parsed_body["error"]

    assert_no_difference "NewsletterSubscription.count" do
      post "/newsletter_subscription", params: { email_address: "reader@example.com", website: "x" },
                                       headers: { "HTTP_REFERER" => "http://www.example.com/" }
    end
    assert_redirected_to "http://www.example.com/"
    assert_equal RequiresHuman::MESSAGE, flash[:alert]
  end

  test "without Turnstile configured a signup needs no token and sends one email" do
    assert_not HumanCheck.enabled?
    assert_difference "User.count", 1 do
      assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
        post "/registration", params: { email_address: "person@example.com" }, as: :json
      end
    end
    assert_response :success
    assert_equal "/pending_verification", response.parsed_body["redirect_url"]
  end

  test "with Turnstile on a signup without a token is refused" do
    with_turnstile do
      assert_no_difference "User.count" do
        post "/registration", params: { email_address: "person@example.com" }, as: :json
      end
      assert_response :unprocessable_entity
      assert_equal RequiresHuman::MESSAGE, response.parsed_body["error"]
    end
  end

  test "with Turnstile on a token Cloudflare accepts signs up" do
    with_turnstile do
      verification = stub_request(:post, SITEVERIFY)
        .with(body: { "secret" => SECRET_KEY, "response" => "token-1", "remoteip" => "127.0.0.1" })
        .to_return(status: 200, body: { success: true }.to_json, headers: { "Content-Type" => "application/json" })

      assert_difference "User.count", 1 do
        post "/registration", params: { email_address: "person@example.com", "cf-turnstile-response" => "token-1" }, as: :json
      end
      assert_response :success
      assert_requested verification
    end
  end

  test "with Turnstile on a token Cloudflare rejects is refused" do
    with_turnstile do
      stub_request(:post, SITEVERIFY)
        .to_return(status: 200, body: { success: false, "error-codes" => [ "invalid-input-response" ] }.to_json)

      assert_no_difference "User.count" do
        post "/registration", params: { email_address: "person@example.com", "cf-turnstile-response" => "stale" }, as: :json
      end
      assert_response :unprocessable_entity
    end
  end

  test "with Turnstile on an unreachable verifier refuses rather than letting the request through" do
    with_turnstile do
      stub_request(:post, SITEVERIFY).to_timeout

      assert_no_difference "User.count" do
        post "/registration", params: { email_address: "person@example.com", "cf-turnstile-response" => "token-2" }, as: :json
      end
      assert_response :unprocessable_entity

      stub_request(:post, SITEVERIFY).to_return(status: 502, body: "bad gateway")
      assert_no_difference "NewsletterSubscription.count" do
        post "/newsletter_subscription", params: { email_address: "reader@example.com", "cf-turnstile-response" => "token-3" }, as: :json
      end
      assert_response :unprocessable_entity
    end
  end

  test "with Turnstile on the full form posts its token with the form" do
    with_turnstile do
      stub_request(:post, SITEVERIFY)
        .with(body: hash_including("response" => "token-4"))
        .to_return(status: 200, body: { success: true }.to_json)

      assert_difference "User.count", 1 do
        post "/registration", params: {
          user: { email_address: "person@example.com", password: "password123", password_confirmation: "password123" },
          "cf-turnstile-response" => "token-4"
        }
      end
      assert_redirected_to "/pending_verification"
    end
  end

  test "the Turnstile loader renders explicitly and names no onload callback" do
    params = URI.decode_www_form(URI(HumanCheckHelper::TURNSTILE_SCRIPT_URL).query).to_h
    assert_equal "explicit", params["render"]
    assert_nil params["onload"],
      "api.js warns when the named onload callback is not defined before it runs; the controller waits on the script's load event instead"
  end

  test "the registration page carries the honeypot and, with Turnstile on, the widget and its loader" do
    get "/registration/new"
    assert_response :success
    assert_select "form input[name=website][tabindex='-1'][autocomplete=off]", 1
    assert_select ".human-check-turnstile", 0
    assert_select "script[src^=?]", HumanCheckHelper::TURNSTILE_SCRIPT_URL, 0

    with_turnstile do
      get "/registration/new"
      assert_response :success
      assert_select "form .human-check-turnstile[data-controller=turnstile][data-turnstile-sitekey-value=?]", SITE_KEY, 1
      assert_select "script[src^=?]", HumanCheckHelper::TURNSTILE_SCRIPT_URL, 1
      assert_no_match SECRET_KEY, response.body
    end
  end

  test "every landing page form carries the honeypot" do
    get "/"
    assert_response :success
    forms = css_select("form[action='/registration'], form[action='/newsletter_subscription']")
    assert_operator forms.length, :>=, 1
    forms.each do |form|
      assert_equal 1, form.css("input[name=website]").length, "#{form['id']} is missing the honeypot"
    end
  end

  test "an unverified address signing up again gets at most one verification email every ten minutes" do
    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
      post "/registration", params: { email_address: "person@example.com" }, as: :json
      assert_response :success
      post "/registration", params: { email_address: "person@example.com" }, as: :json
      assert_response :success
      assert_match(/resent/, response.parsed_body["message"])
    end

    travel 11.minutes do
      assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
        post "/registration", params: { email_address: "person@example.com" }, as: :json
        assert_response :success
      end
    end
  end

  private

  def with_turnstile
    previous = ENV.slice("TURNSTILE_SITE_KEY", "TURNSTILE_SECRET_KEY")
    ENV["TURNSTILE_SITE_KEY"] = SITE_KEY
    ENV["TURNSTILE_SECRET_KEY"] = SECRET_KEY
    yield
  ensure
    ENV.delete("TURNSTILE_SITE_KEY")
    ENV.delete("TURNSTILE_SECRET_KEY")
    ENV.update(previous)
  end
end

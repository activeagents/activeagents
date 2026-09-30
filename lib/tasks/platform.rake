# frozen_string_literal: true

namespace :platform do
  desc "Create a signed-in-ready user, the account they own and a named API key, and print the key " \
       "(EMAIL=, PASSWORD= for a new user, KEY_NAME=local, PLAN= to comp a plan by slug; " \
       "CONFIRM=yes where RAILS_ENV is production)"
  task bootstrap_account: :environment do
    # A local run of the production image is RAILS_ENV=production too, so the
    # guard is an explicit confirmation rather than a refusal.
    if Rails.env.production? && ENV["CONFIRM"] != "yes"
      abort "This creates a login and an API key in a production environment. Rerun with CONFIRM=yes to proceed."
    end

    email = ENV["EMAIL"].presence || abort("EMAIL is required")

    user = User.find_or_initialize_by(email_address: email)
    if user.new_record?
      password = ENV["PASSWORD"].presence || abort("PASSWORD is required to create #{email}")
      user.update!(password: password, password_confirmation: password, email_verified: true, profile_completed: true)
    end

    account = user.owned_accounts.first || Account.create!(owner: user, name: ENV["ACCOUNT_NAME"].presence || "#{user.display_name}'s Workspace").tap do |created|
      created.account_memberships.create!(user: user, role: "owner")
    end

    # A comp is a fake_processor subscription, which Account#current_plan reads
    # as the plan with that slug. It is added beside any real processor, and
    # refused for an account that already pays, whose plan comes from Stripe.
    if (slug = ENV["PLAN"].presence)
      Plan.find_by!(slug: slug)
      subscription = account.active_subscription
      if subscription && subscription.customer.processor != "fake_processor"
        abort "#{email}'s account has an active #{subscription.customer.processor} subscription; not comping it"
      end

      unless subscription&.processor_plan == slug
        account.add_payment_processor(:fake_processor, allow_fake: true).subscribe(plan: slug)
      end
    end

    key_name = ENV["KEY_NAME"].presence || "local"
    api_key = account.api_keys.find_by(name: key_name) || account.api_keys.create!(name: key_name)

    warn "#{email}: account #{account.id} (#{account.reload.current_plan&.slug || 'free'} plan), API key #{key_name.inspect}"
    puts "ACTIVEAGENTS_API_KEY=#{api_key.token}"
  end
end

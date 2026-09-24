# frozen_string_literal: true

namespace :platform do
  desc "Create a signed-in-ready user, their account and a named API key, and print the key " \
       "(EMAIL=, PASSWORD= for a new user, KEY_NAME=local, PLAN= to comp a plan by slug)"
  task bootstrap_account: :environment do
    email = ENV["EMAIL"].presence || abort("EMAIL is required")

    user = User.find_or_initialize_by(email_address: email)
    if user.new_record?
      password = ENV["PASSWORD"].presence || abort("PASSWORD is required to create #{email}")
      user.update!(password: password, password_confirmation: password, email_verified: true, profile_completed: true)
    end

    account = user.primary_account || Account.create!(owner: user, name: ENV["ACCOUNT_NAME"].presence || "#{user.display_name}'s Workspace").tap do |created|
      created.account_memberships.create!(user: user, role: "owner")
    end

    # A comp is a fake_processor subscription, which Account#current_plan reads
    # as the plan with that slug.
    if (slug = ENV["PLAN"].presence)
      Plan.find_by!(slug: slug)
      unless account.active_subscription&.processor_plan == slug
        account.set_payment_processor(:fake_processor, allow_fake: true)
        account.payment_processor.subscribe(plan: slug)
      end
    end

    key_name = ENV["KEY_NAME"].presence || "local"
    api_key = account.api_keys.find_by(name: key_name) || account.api_keys.create!(name: key_name)

    warn "#{email}: account #{account.id} (#{account.reload.current_plan&.slug || 'free'} plan), API key #{key_name.inspect}"
    puts "ACTIVEAGENTS_API_KEY=#{api_key.token}"
  end
end

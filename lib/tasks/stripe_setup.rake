namespace :stripe do
  desc "Configure only staging Pro test prices; requires STRIPE_EXPECTED_ACCOUNT_ID"
  task setup_pro: :environment do
    result = StagingProBilling.new(expected_account_id: ENV["STRIPE_EXPECTED_ACCOUNT_ID"]).configure!
    puts "STAGING_PRO_BILLING #{JSON.generate(result)}"
  rescue StagingProBilling::ConfigurationError => error
    abort error.message
  end

  desc "Use stripe:setup_pro for scoped, repeatable staging setup"
  task setup: :environment do
    abort "Broad catalog creation is disabled. Use stripe:setup_pro with STRIPE_EXPECTED_ACCOUNT_ID for staging test billing."
  end
end

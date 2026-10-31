namespace :hunts do
  desc "Queue a discovery run for every scheduled hunt that is due (what Solid Queue does on its own on the schedule in config/recurring.yml)"
  task run_due: :environment do
    queued = ScheduleHuntsJob.perform_now
    puts "Queued #{queued} hunt#{'s' unless queued == 1}."
  end

  desc "Run one hunt now, synchronously: bin/rails hunts:run HUNT_ID=1"
  task run: :environment do
    hunt = Hunt.find(ENV.fetch("HUNT_ID"))
    run = hunt.discovery_runs.create!(user: hunt.user, trigger: "manual", fee_cents: hunt.user.plan.run_fee_cents)
    run.perform!
    puts "Run #{run.id}: #{run.status}, #{run.new_findings_count} new findings, scored by #{run.scored_by}."
    puts run.error_message if run.error_message.present?
  end
end

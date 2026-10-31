# Two accounts and three hunts, so the app has something to show the moment
# it boots. Idempotent, so it is safe to run again.
#
#   admin@example.com     / password   the install's admin: sees /activeagents
#   collector@example.com / password   a collector on the Collector plan
#
# Nothing here runs the agent; open a hunt and press "Run hunt" for that.

admin = User.find_or_create_by!(email_address: "admin@example.com") do |user|
  user.name = "Admin"
  user.password = "password"
end
admin.update!(admin: true)

collector = User.find_or_create_by!(email_address: "collector@example.com") do |user|
  user.name = "Dana"
  user.password = "password"
end
Billing.subscribe!(collector, :collector) unless collector.plan.key == "collector"

[
  {
    title: "Patagonia Synchilla Snap-T, 90s, made in USA",
    brand: "Patagonia",
    category: "clothing",
    keywords: "synchilla, snap-t, fleece, pullover, 90s",
    sizes: "M, L",
    max_price: 150,
    condition: "vintage",
    frequency: "daily",
    description: "The original oval-logo Snap-T with the nylon placket. Forest green or navy ideally. No kids sizes, no later Colombia-made ones."
  },
  {
    title: "Seiko 6139 Pogue, yellow dial",
    brand: "Seiko",
    category: "watches",
    keywords: "6139, 6139-6002, pogue, chronograph",
    max_price: 1500,
    condition: "vintage",
    frequency: "weekly",
    description: "A 1970s 6139-6002 with the yellow dial and Pepsi bezel, serviced within the last few years."
  },
  {
    title: "Leica M6 Classic, black chrome",
    brand: "Leica",
    category: "cameras",
    keywords: "m6, m6 classic, rangefinder, 0.72",
    max_price: 3500,
    condition: "used",
    frequency: "manual",
    description: "A working M6 Classic with a clear finder and an accurate meter. Not an M6 TTL, and nothing described as a replica or display body."
  }
].each do |attrs|
  collector.hunts.find_or_create_by!(title: attrs[:title]) do |hunt|
    hunt.assign_attributes(attrs.except(:title))
  end
end

puts "Seeded #{User.count} users and #{Hunt.count} hunts."
puts "Sign in as admin@example.com or collector@example.com with the password 'password'."

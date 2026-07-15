# Sample tickets so the inbox has something to triage the moment it boots.
# Idempotent (find_or_create_by) because the staging container re-seeds on
# every start — its SQLite database is ephemeral.
[
  {
    subject: "Charged twice this month",
    customer_email: "dana@example.com",
    body: "Hi — my card statement shows two charges for July ($99 each) but I only have one workspace. Can you refund the duplicate charge? Invoice numbers are INV-2041 and INV-2043."
  },
  {
    subject: "Password reset email never arrives",
    customer_email: "sam@example.net",
    body: "I've clicked 'Forgot password?' four times and nothing shows up, not even in spam. I'm locked out of our account and we have a launch tomorrow. Please help ASAP!"
  },
  {
    subject: "How do I export everything to CSV?",
    customer_email: "priya@example.org",
    body: "We're doing a quarterly backup and I'd like a full export of our records. Is there a bulk CSV download, or do I need to script it against the API?"
  },
  {
    subject: "Love the product — one feature idea",
    customer_email: "jules@example.com",
    body: "We've been using the app for six months and it's great. Any chance you could add a weekly digest email summarizing workspace activity? Our leads would read that religiously."
  }
].each do |attrs|
  Ticket.find_or_create_by!(subject: attrs[:subject]) do |ticket|
    ticket.customer_email = attrs[:customer_email]
    ticket.body = attrs[:body]
  end
end

puts "Seeded #{Ticket.count} tickets."

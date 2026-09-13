class ApplicationMailbox < ActionMailbox::Base
  # Support addresses, including the +tagged reply addresses that conversations
  # thread on (support+f3a9c1d8@example.com).
  routing(/\Asupport(\+[^@]+)?@/i => :support)

  # This demo is a support inbox and nothing else, so anything that reaches it
  # goes to the same mailbox rather than raising an unroutable error in the
  # ingress. A real app routes per address and leaves the rest unrouted.
  routing all: :support
end

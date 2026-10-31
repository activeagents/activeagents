# The digest a collector gets when a run turns up new finds.
class FindingsMailer < ApplicationMailer
  def digest(run)
    @run = run
    @hunt = run.hunt
    @findings = run.findings.by_score

    count = @findings.size
    mail to: @hunt.user.email_address,
         subject: "#{count} new find#{'s' unless count == 1} for #{@hunt.title}"
  end
end

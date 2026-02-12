class WritingAgent < ApplicationAgent
  def draft
    @topic = params[:message]
    @research = params[:session]&.research_findings
    @existing_draft = params[:session]&.draft_content

    prompt(
      message: params[:message],
      tools: [
        {
          name: "outline",
          description: "Create a structured outline for a document",
          parameters: {
            type: "object",
            properties: {
              topic: { type: "string", description: "Topic of the document" },
              sections: { type: "integer", description: "Number of sections" }
            },
            required: ["topic"]
          }
        },
        {
          name: "expand_section",
          description: "Expand a section outline into full prose",
          parameters: {
            type: "object",
            properties: {
              title: { type: "string", description: "Section title" },
              key_points: { type: "string", description: "Key points to cover" }
            },
            required: ["title"]
          }
        }
      ]
    )
  end

  def outline(topic:, sections: 4)
    {
      title: "Report: #{topic}",
      sections: [
        { heading: "Introduction", key_points: "Background, scope, objectives" },
        { heading: "Key Findings", key_points: "Main discoveries and data points" },
        { heading: "Analysis", key_points: "Interpretation of findings, implications" },
        { heading: "Conclusion", key_points: "Summary, recommendations, future directions" }
      ].first(sections)
    }
  end

  def expand_section(title:, key_points: "")
    {
      heading: title,
      content: "This section covers #{title.downcase}. #{key_points}. " \
               "Based on the available research, several important themes emerge " \
               "that warrant careful consideration and further investigation."
    }
  end
end

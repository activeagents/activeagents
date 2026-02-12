class ReportBuilderAgent < ApplicationAgent
  def build_report
    @topic = params[:message]
    @research = params[:session]&.research_findings
    @draft = params[:session]&.draft_content

    prompt(
      message: params[:message],
      tools: [
        {
          name: "compile_citations",
          description: "Compile citations from research sources into a formatted bibliography",
          parameters: {
            type: "object",
            properties: {
              format: { type: "string", description: "Citation format (apa, mla, chicago)", enum: ["apa", "mla", "chicago"] }
            },
            required: ["format"]
          }
        },
        {
          name: "format_report",
          description: "Format the final report with sections, citations, and metadata",
          parameters: {
            type: "object",
            properties: {
              title: { type: "string", description: "Report title" },
              include_toc: { type: "boolean", description: "Include table of contents" }
            },
            required: ["title"]
          }
        }
      ]
    )
  end

  def compile_citations(format: "apa")
    sources = @research.is_a?(Hash) ? (@research["sources"] || []) : []

    citations = sources.map.with_index(1) do |source, i|
      authors = source["authors"]&.join(", ") || "Unknown"
      title = source["title"] || "Untitled"
      year = source["year"] || "n.d."
      journal = source["journal"] || ""

      case format
      when "apa"
        "[#{i}] #{authors} (#{year}). #{title}. #{journal}."
      when "mla"
        "[#{i}] #{authors}. \"#{title}.\" #{journal}, #{year}."
      when "chicago"
        "[#{i}] #{authors}. #{title}. #{journal} (#{year})."
      end
    end

    { citations: citations, format: format, count: citations.length }
  end

  def format_report(title:, include_toc: true)
    sections = []
    sections << "# #{title}"
    sections << ""

    if include_toc
      sections << "## Table of Contents"
      sections << "1. Introduction"
      sections << "2. Research Findings"
      sections << "3. Analysis"
      sections << "4. Conclusion"
      sections << "5. References"
      sections << ""
    end

    if @draft.present?
      sections << @draft
      sections << ""
    end

    if @research.present? && @research["sources"].present?
      sections << "## References"
      @research["sources"].each_with_index do |source, i|
        authors = source["authors"]&.join(", ") || "Unknown"
        sections << "[#{i + 1}] #{authors} (#{source["year"]}). #{source["title"]}. #{source["journal"]}."
      end
    end

    { formatted_report: sections.join("\n"), title: title }
  end
end

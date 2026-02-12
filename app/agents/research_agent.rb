class ResearchAgent < ApplicationAgent
  def investigate
    @topic = params[:message]
    @existing_research = params[:session]&.research_findings

    prompt(
      message: params[:message],
      tools: [
        {
          name: "search_web",
          description: "Search the web for information on a topic",
          parameters: {
            type: "object",
            properties: {
              query: { type: "string", description: "Search query" }
            },
            required: ["query"]
          }
        },
        {
          name: "find_sources",
          description: "Find academic and authoritative sources on a topic",
          parameters: {
            type: "object",
            properties: {
              topic: { type: "string", description: "Topic to find sources for" },
              count: { type: "integer", description: "Number of sources to find" }
            },
            required: ["topic"]
          }
        }
      ]
    )
  end

  def search_web(query:)
    # Simulated search results
    {
      results: [
        {
          title: "Understanding #{query} - A Comprehensive Guide",
          url: "https://example.com/guide/#{query.parameterize}",
          snippet: "A thorough exploration of #{query}, covering key concepts, recent developments, and practical applications."
        },
        {
          title: "#{query}: Latest Research and Findings",
          url: "https://example.com/research/#{query.parameterize}",
          snippet: "Recent studies have shown significant advances in #{query}, with implications for multiple fields."
        },
        {
          title: "Expert Analysis: The Future of #{query}",
          url: "https://example.com/analysis/#{query.parameterize}",
          snippet: "Leading experts weigh in on the trajectory of #{query} and what to expect in coming years."
        }
      ]
    }
  end

  def find_sources(topic:, count: 3)
    # Simulated academic sources
    sources = [
      {
        title: "Foundations of #{topic}",
        authors: ["Dr. A. Smith", "Dr. B. Johnson"],
        year: 2024,
        journal: "Journal of Advanced Research",
        doi: "10.1234/jar.2024.#{topic.parameterize}",
        url: "https://doi.org/10.1234/jar.2024.#{topic.parameterize}"
      },
      {
        title: "A Systematic Review of #{topic}",
        authors: ["Dr. C. Williams", "Prof. D. Brown"],
        year: 2025,
        journal: "Annual Review of Technology",
        doi: "10.5678/art.2025.#{topic.parameterize}",
        url: "https://doi.org/10.5678/art.2025.#{topic.parameterize}"
      },
      {
        title: "#{topic}: Emerging Trends and Applications",
        authors: ["Dr. E. Davis"],
        year: 2025,
        journal: "IEEE Transactions",
        doi: "10.9012/ieee.2025.#{topic.parameterize}",
        url: "https://doi.org/10.9012/ieee.2025.#{topic.parameterize}"
      }
    ]

    { sources: sources.first(count) }
  end
end

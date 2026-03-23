defmodule Vaos.Ledger.Research.Paper do
  @moduledoc """
  Paper generation with section-by-section LLM synthesis.
  Ported from denario_ex's PaperWorkflow: prompt templates, LaTeX rendering,
  bibliography generation.

  All LLM calls go through an injected llm_fn callback.
  """

  require Logger

  @type llm_fn :: (String.t() -> {:ok, String.t()} | {:error, term()})

  @type paper :: %{
          title: String.t(),
          abstract: String.t(),
          introduction: String.t(),
          methods: String.t(),
          results: String.t(),
          conclusions: String.t(),
          keywords: String.t(),
          bibliography: [map()]
        }

  @type paper_context :: %{
          idea: String.t(),
          methodology: String.t(),
          results: String.t(),
          literature: String.t()
        }

  @doc """
  Synthesize a full paper from research context using llm_fn for each section.
  Returns {:ok, paper} or {:error, reason}.
  """
  @spec synthesize(paper_context(), llm_fn(), keyword()) :: {:ok, paper()} | {:error, term()}
  def synthesize(context, llm_fn, opts \\ []) do
    literature_sources = Keyword.get(opts, :literature_sources, [])
    citation_context = format_citation_context(literature_sources)

    with {:ok, title_and_abstract} <-
           generate_title_and_abstract(context, llm_fn, citation_context),
         {:ok, introduction} <-
           generate_section("Introduction", context, llm_fn, citation_context, title_and_abstract),
         {:ok, methods} <-
           generate_section("Methods", context, llm_fn, citation_context, title_and_abstract),
         {:ok, results} <-
           generate_section("Results", context, llm_fn, citation_context, title_and_abstract),
         {:ok, conclusions} <-
           generate_section("Conclusions", context, llm_fn, citation_context, title_and_abstract),
         {:ok, keywords} <- generate_keywords(context, llm_fn) do
      {:ok,
       %{
         title: title_and_abstract.title,
         abstract: title_and_abstract.abstract,
         introduction: introduction,
         methods: methods,
         results: results,
         conclusions: conclusions,
         keywords: keywords,
         bibliography: literature_sources
       }}
    end
  end

  @doc """
  Render a paper struct to LaTeX source.
  """
  @spec to_latex(paper()) :: String.t()
  def to_latex(paper) do
    bib_block =
      if paper.bibliography != [] do
        "\\bibliography{bibliography}\n\\bibliographystyle{unsrt}"
      else
        ""
      end

    """
    \\documentclass{article}
    \\usepackage{amsmath}
    \\usepackage{graphicx}
    \\usepackage{natbib}

    \\begin{document}
    \\title{#{sanitize_latex(paper.title)}}
    \\author{Vaos Ledger}
    \\maketitle

    \\begin{abstract}
    #{sanitize_latex(paper.abstract)}
    \\end{abstract}

    \\section{Introduction}
    #{sanitize_latex(paper.introduction)}

    \\section{Methods}
    #{sanitize_latex(paper.methods)}

    \\section{Results}
    #{sanitize_latex(paper.results)}

    \\section{Conclusions}
    #{sanitize_latex(paper.conclusions)}

    #{bib_block}
    \\end{document}
    """
  end

  @doc """
  Generate a BibTeX bibliography string from literature sources.
  """
  @spec generate_bibliography([map()]) :: String.t()
  def generate_bibliography(sources) do
    Enum.map_join(sources, "\n\n", fn source ->
      id = Map.get(source, :paper_id, "paper")

      authors =
        source
        |> Map.get(:authors, [])
        |> Enum.join(" and ")

      title = Map.get(source, :title, "Untitled")
      year = Map.get(source, :year, "2025")
      url = Map.get(source, :url, "")

      """
      @article{#{id},
        title = {#{escape_bib(title)}},
        author = {#{escape_bib(authors)}},
        year = {#{year}},
        url = {#{escape_bib(url || "")}}
      }
      """
    end)
  end

  # -- Prompt Templates (ported from denario_ex WorkflowPrompts) --

  defp generate_title_and_abstract(context, llm_fn, citation_context) do
    prompt = """
    You are a scientist. Write a title and abstract for the following research paper.

    Idea:
    #{context.idea}

    Methods:
    #{context.methodology}

    Results:
    #{context.results}

    Available citations:
    #{if citation_context == "", do: "none", else: citation_context}

    Respond in this exact format:

    TITLE: <your title here>

    ABSTRACT: <your abstract here>
    """

    case llm_fn.(prompt) do
      {:ok, response} ->
        title = extract_field(response, "TITLE") || "Untitled Paper"
        abstract = extract_field(response, "ABSTRACT") || ""
        {:ok, %{title: title, abstract: abstract}}

      {:error, reason} ->
        {:error, {:title_abstract_failed, reason}}
    end
  end

  defp generate_section(section_name, context, llm_fn, citation_context, title_abstract) do
    prompt = """
    You are a scientist. Write the #{section_name} section of a research paper.

    Paper title: #{title_abstract.title}
    Paper abstract: #{title_abstract.abstract}

    Idea:
    #{context.idea}

    Methods:
    #{context.methodology}

    Results:
    #{context.results}

    Available citations:
    #{if citation_context == "", do: "none", else: citation_context}

    Write only the content for the #{section_name} section.
    Do not include the section heading itself.
    Respond with just the section text.
    """

    case llm_fn.(prompt) do
      {:ok, text} -> {:ok, String.trim(text)}
      {:error, reason} -> {:error, {:section_failed, section_name, reason}}
    end
  end

  defp generate_keywords(context, llm_fn) do
    prompt = """
    Generate five concise paper keywords for the following research.

    Idea: #{context.idea}
    Methods: #{context.methodology}
    Results: #{context.results}

    Respond with a comma-separated list of keywords only.
    """

    case llm_fn.(prompt) do
      {:ok, text} -> {:ok, String.trim(text)}
      {:error, reason} -> {:error, {:keywords_failed, reason}}
    end
  end

  # -- Helpers --

  defp extract_field(text, field) do
    case Regex.run(~r/#{field}:\s*(.+?)(?:\n\n|\n[A-Z]+:|\z)/s, text) do
      [_, match] -> String.trim(match)
      nil -> nil
    end
  end

  defp format_citation_context([]), do: ""

  defp format_citation_context(sources) do
    Enum.map_join(sources, "\n", fn source ->
      id = Map.get(source, :paper_id, "paper")
      authors = source |> Map.get(:authors, []) |> Enum.join(", ")
      title = Map.get(source, :title, "Untitled")
      year = Map.get(source, :year, "")
      "#{id}: #{title} (#{year}) by #{authors}"
    end)
  end

  defp sanitize_latex(nil), do: ""

  defp sanitize_latex(text) when is_binary(text) do
    text
    |> String.replace(~r/(?<!\\)_/, "\\_")
    |> String.replace(~r/(?<!\\)%/, "\\%")
    |> String.replace(~r/(?<!\\)&/, "\\&")
    |> String.replace(~r/(?<!\\)#/, "\\#")
  end

  defp escape_bib(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("{", "\\{")
    |> String.replace("}", "\\}")
    |> String.replace("&", "\\&")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end

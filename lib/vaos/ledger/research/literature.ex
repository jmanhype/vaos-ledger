defmodule Vaos.Ledger.Research.Literature do
  @moduledoc """
  Literature search across Semantic Scholar and OpenAlex.
  All HTTP calls go through an injected http_fn callback.
  """

  require Logger

  @semantic_scholar_url "https://api.semanticscholar.org/graph/v1/paper/search"
  @openalex_url "https://api.openalex.org/works"
  @ss_fields "title,authors,year,abstract,url,paperId,citationCount,publicationTypes"

  @type paper :: %{
          paper_id: String.t(),
          title: String.t(),
          authors: [String.t()],
          year: integer() | nil,
          abstract: String.t() | nil,
          url: String.t() | nil,
          citation_count: integer(),
          source: :semantic_scholar | :openalex
        }

  @type http_fn :: (String.t(), keyword() -> {:ok, map()} | {:error, term()})

  @doc """
  Search Semantic Scholar for papers matching the query.
  Returns {:ok, [paper]} or {:error, reason}.

  http_fn receives (url, opts) where opts includes :params and optional :headers.
  """
  @spec search_semantic_scholar(String.t(), http_fn(), keyword()) ::
          {:ok, [paper()]} | {:error, term()}
  def search_semantic_scholar(query, http_fn, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    api_key = Keyword.get(opts, :api_key, nil)
    publication_types = Keyword.get(opts, :publication_types, nil)

    headers = if api_key, do: [{"x-api-key", api_key}], else: []

    params = [query: query, limit: limit, fields: @ss_fields]
    params = if publication_types do
      # SS API accepts publicationTypes filter e.g. "Review,MetaAnalysis"
      params ++ [publicationTypes: publication_types]
    else
      params
    end

    case http_fn.(@semantic_scholar_url,
           params: params,
           headers: headers
         ) do
      {:ok, %{"data" => data}} when is_list(data) ->
        {:ok, Enum.map(data, &normalize_ss_paper/1)}

      {:ok, %{"data" => nil}} ->
        {:ok, []}

      {:ok, body} when is_map(body) ->
        case Map.get(body, "data") do
          nil -> {:ok, []}
          data when is_list(data) -> {:ok, Enum.map(data, &normalize_ss_paper/1)}
        end

      {:error, reason} ->
        Logger.warning("Semantic Scholar search failed: #{inspect(reason)}")
        {:error, {:semantic_scholar_failed, reason}}
    end
  end

  @doc """
  Search OpenAlex as a fallback. Same http_fn interface.
  """
  @spec search_openalex(String.t(), http_fn(), keyword()) ::
          {:ok, [paper()]} | {:error, term()}
  def search_openalex(query, http_fn, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    type_filter = Keyword.get(opts, :type, nil)

    # Build filter string — always require abstract and recent date
    base_filter = "has_abstract:true,from_publication_date:2010-01-01"
    filter = if type_filter do
      # OA accepts type filter e.g. "type:review"
      "#{base_filter},type:#{type_filter}"
    else
      base_filter
    end

    case http_fn.(@openalex_url,
           params: [
             {"search", query},
             {"per-page", Integer.to_string(limit)},
             {"select",
              "id,title,publication_year,cited_by_count,authorships,abstract_inverted_index"},
             {"filter", filter}
           ]
         ) do
      {:ok, %{"results" => results}} when is_list(results) ->
        {:ok, Enum.map(results, &normalize_openalex_work/1)}

      {:error, reason} ->
        Logger.warning("OpenAlex search failed: #{inspect(reason)}")
        {:error, {:openalex_failed, reason}}
    end
  end

  @doc """
  Search both sources with automatic fallback.
  Tries Semantic Scholar first, falls back to OpenAlex on failure.
  """
  @spec search(String.t(), http_fn(), keyword()) :: {:ok, [paper()]} | {:error, term()}
  def search(query, http_fn, opts \\ []) do
    case search_semantic_scholar(query, http_fn, opts) do
      {:ok, papers} when papers != [] ->
        {:ok, papers}

      _ ->
        Logger.info("Falling back to OpenAlex for: #{query}")
        search_openalex(query, http_fn, opts)
    end
  end

  @doc """
  Rank papers by relevance to the given context terms.
  Uses term overlap scoring similar to denario_ex's literature workflow.
  """
  @spec rank_papers([paper()], String.t()) :: [paper()]
  def rank_papers(papers, context_text) do
    context_terms = tokenize(context_text)

    Enum.sort_by(
      papers,
      fn paper ->
        title_terms = tokenize(paper.title || "")
        abstract_terms = tokenize(paper.abstract || "")

        title_overlap = MapSet.intersection(context_terms, title_terms) |> MapSet.size()
        abstract_overlap = MapSet.intersection(context_terms, abstract_terms) |> MapSet.size()
        year_bonus = year_bonus(paper.year)
        citation_bonus = :math.log10((paper.citation_count || 0) + 1)

        title_overlap * 3.0 + abstract_overlap + year_bonus + citation_bonus
      end,
      :desc
    )
  end

  # -- Private --

  defp normalize_ss_paper(paper) do
    authors =
      paper
      |> Map.get("authors", [])
      |> List.wrap()
      |> Enum.map(fn a -> Map.get(a, "name", "Unknown") end)

    %{
      paper_id: Map.get(paper, "paperId", ""),
      title: Map.get(paper, "title", ""),
      authors: authors,
      year: Map.get(paper, "year"),
      abstract: Map.get(paper, "abstract"),
      url: Map.get(paper, "url"),
      citation_count: Map.get(paper, "citationCount", 0) || 0,
      publication_types: Map.get(paper, "publicationTypes") || [],
      source: :semantic_scholar
    }
  end

  defp normalize_openalex_work(work) do
    authors =
      work
      |> Map.get("authorships", [])
      |> List.wrap()
      |> Enum.map(fn a -> get_in(a, ["author", "display_name"]) || "Unknown" end)

    %{
      paper_id: work |> Map.get("id", "") |> String.replace("https://openalex.org/", ""),
      title: Map.get(work, "title", ""),
      authors: authors,
      year: Map.get(work, "publication_year"),
      abstract: reconstruct_abstract(Map.get(work, "abstract_inverted_index")),
      url: Map.get(work, "id"),
      citation_count: Map.get(work, "cited_by_count", 0) || 0,
      source: :openalex
    }
  end

  defp reconstruct_abstract(nil), do: nil

  defp reconstruct_abstract(index) when is_map(index) do
    index
    |> Enum.flat_map(fn {word, positions} ->
      Enum.map(positions, fn pos -> {pos, word} end)
    end)
    |> Enum.sort_by(fn {pos, _} -> pos end)
    |> Enum.map_join(" ", fn {_, word} -> word end)
  end

  defp reconstruct_abstract(_), do: nil

  defp tokenize(text) do
    stopwords =
      MapSet.new(
        ~w(a an and are as at be by for from in into is it of on or that the this to using with over within)
      )

    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]+/u, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(String.length(&1) < 3 or MapSet.member?(stopwords, &1)))
    |> MapSet.new()
  end

  defp year_bonus(nil), do: 0.0
  defp year_bonus(year) when year >= 2020, do: 2.0
  defp year_bonus(year) when year >= 2015, do: 1.0
  defp year_bonus(_year), do: 0.0
end

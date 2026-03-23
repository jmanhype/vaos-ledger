defmodule Vaos.Ledger.Research.LiteratureTest do
  use ExUnit.Case, async: true

  alias Vaos.Ledger.Research.Literature

  describe "search_semantic_scholar/3" do
    test "parses Semantic Scholar response" do
      http_fn = fn _url, _opts ->
        {:ok,
         %{
           "data" => [
             %{
               "paperId" => "abc123",
               "title" => "Test Paper",
               "authors" => [%{"name" => "Alice"}, %{"name" => "Bob"}],
               "year" => 2024,
               "abstract" => "This is a test abstract.",
               "url" => "https://example.com/paper",
               "citationCount" => 42
             }
           ]
         }}
      end

      {:ok, papers} = Literature.search_semantic_scholar("test query", http_fn)
      assert length(papers) == 1
      [paper] = papers
      assert paper.paper_id == "abc123"
      assert paper.title == "Test Paper"
      assert paper.authors == ["Alice", "Bob"]
      assert paper.year == 2024
      assert paper.citation_count == 42
      assert paper.source == :semantic_scholar
    end

    test "handles empty data" do
      http_fn = fn _url, _opts -> {:ok, %{"data" => nil}} end
      {:ok, papers} = Literature.search_semantic_scholar("query", http_fn)
      assert papers == []
    end

    test "handles http error" do
      http_fn = fn _url, _opts -> {:error, :timeout} end
      {:error, {:semantic_scholar_failed, :timeout}} = Literature.search_semantic_scholar("query", http_fn)
    end
  end

  describe "search_openalex/3" do
    test "parses OpenAlex response with inverted abstract" do
      http_fn = fn _url, _opts ->
        {:ok,
         %{
           "results" => [
             %{
               "id" => "https://openalex.org/W123",
               "title" => "OpenAlex Paper",
               "publication_year" => 2023,
               "cited_by_count" => 10,
               "authorships" => [
                 %{"author" => %{"display_name" => "Carol"}}
               ],
               "abstract_inverted_index" => %{
                 "Hello" => [0],
                 "world" => [1]
               }
             }
           ]
         }}
      end

      {:ok, papers} = Literature.search_openalex("query", http_fn)
      assert length(papers) == 1
      [paper] = papers
      assert paper.paper_id == "W123"
      assert paper.title == "OpenAlex Paper"
      assert paper.abstract == "Hello world"
      assert paper.source == :openalex
    end
  end

  describe "search/3" do
    test "falls back to OpenAlex when Semantic Scholar fails" do
      call_count = :counters.new(1, [:atomics])

      http_fn = fn url, _opts ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        if count == 1 do
          # First call is Semantic Scholar - fail it
          {:error, :rate_limited}
        else
          # Second call is OpenAlex
          {:ok,
           %{
             "results" => [
               %{
                 "id" => "https://openalex.org/W456",
                 "title" => "Fallback Paper",
                 "publication_year" => 2022,
                 "cited_by_count" => 5,
                 "authorships" => [],
                 "abstract_inverted_index" => %{"test" => [0]}
               }
             ]
           }}
        end
      end

      {:ok, papers} = Literature.search("query", http_fn)
      assert length(papers) == 1
      assert hd(papers).title == "Fallback Paper"
    end
  end

  describe "rank_papers/2" do
    test "ranks papers by relevance to context" do
      papers = [
        %{paper_id: "1", title: "Unrelated Topic", authors: [], year: 2015, abstract: "Something else entirely", url: nil, citation_count: 100, source: :semantic_scholar},
        %{paper_id: "2", title: "Machine Learning Optimization", authors: [], year: 2023, abstract: "Neural network optimization techniques for deep learning", url: nil, citation_count: 10, source: :semantic_scholar},
        %{paper_id: "3", title: "Deep Learning Optimization Methods", authors: [], year: 2024, abstract: "Advanced optimization for neural networks and machine learning models", url: nil, citation_count: 5, source: :semantic_scholar}
      ]

      ranked = Literature.rank_papers(papers, "neural network optimization deep learning")
      # Papers 2 and 3 should rank higher than paper 1
      assert hd(ranked).paper_id in ["2", "3"]
    end
  end
end

defmodule Vaos.Ledger.Research.CodeExecutorTest do
  use ExUnit.Case, async: true

  alias Vaos.Ledger.Research.CodeExecutor

  describe "execute/3" do
    test "runs code through code_fn and returns result" do
      code_fn = fn code, _opts ->
        {:ok, %{stdout: "Result: #{String.length(code)}", stderr: ""}}
      end

      {:ok, result} = CodeExecutor.execute("print('hello')", code_fn)
      assert result.stdout == "Result: 14"
      assert result.stderr == ""
      assert result.exit_code == 0
    end

    test "handles code_fn errors" do
      code_fn = fn _code, _opts -> {:error, :syntax_error} end
      {:error, :syntax_error} = CodeExecutor.execute("bad code", code_fn)
    end
  end

  describe "execute_with_retry/3" do
    test "succeeds on first attempt" do
      code_fn = fn _code, _opts ->
        {:ok, %{stdout: "success", stderr: ""}}
      end

      {:ok, result} = CodeExecutor.execute_with_retry("code", code_fn, max_attempts: 3)
      assert result.stdout == "success"
    end

    test "retries with fix_fn on failure" do
      attempt_counter = :counters.new(1, [:atomics])

      code_fn = fn code, _opts ->
        :counters.add(attempt_counter, 1, 1)
        count = :counters.get(attempt_counter, 1)

        if count < 2 do
          {:error, "NameError: undefined variable"}
        else
          {:ok, %{stdout: "fixed: #{code}", stderr: ""}}
        end
      end

      fix_fn = fn _code, _error ->
        {:ok, "fixed_code"}
      end

      {:ok, result} =
        CodeExecutor.execute_with_retry("original", code_fn,
          max_attempts: 3,
          fix_fn: fix_fn,
          step_id: "test_step"
        )

      assert result.stdout =~ "fixed"
    end

    test "gives up after max attempts" do
      code_fn = fn _code, _opts -> {:error, "always fails"} end
      fix_fn = fn _code, _error -> {:ok, "still broken"} end

      {:error, "always fails"} =
        CodeExecutor.execute_with_retry("code", code_fn,
          max_attempts: 2,
          fix_fn: fix_fn
        )
    end

    test "gives up immediately without fix_fn" do
      code_fn = fn _code, _opts -> {:error, "fails"} end

      {:error, "fails"} =
        CodeExecutor.execute_with_retry("code", code_fn, max_attempts: 3)
    end
  end
end

defmodule Vaos.Ledger.Research.PaperTest do
  use ExUnit.Case, async: true

  alias Vaos.Ledger.Research.Paper

  describe "synthesize/3" do
    test "generates all paper sections via llm_fn" do
      llm_fn = fn prompt ->
        cond do
          String.contains?(prompt, "title and abstract") ->
            {:ok, "TITLE: Test Paper Title\n\nABSTRACT: This is the abstract."}

          String.contains?(prompt, "Write the Introduction section") ->
            {:ok, "This introduces the research."}

          String.contains?(prompt, "Write the Results section") ->
            {:ok, "We found result Y."}

          String.contains?(prompt, "Write the Conclusions section") ->
            {:ok, "We conclude Z."}

          String.contains?(prompt, "Write the Methods section") ->
            {:ok, "We used method X."}

          String.contains?(prompt, "keywords") ->
            {:ok, "AI, ML, testing, research, automation"}

          true ->
            {:ok, "default response"}
        end
      end

      context = %{
        idea: "Test idea",
        methodology: "Test method",
        results: "Test results",
        literature: "Test lit"
      }

      {:ok, paper} = Paper.synthesize(context, llm_fn)
      assert paper.title == "Test Paper Title"
      assert paper.abstract == "This is the abstract."
      assert paper.introduction == "This introduces the research."
      assert paper.methods == "We used method X."
      assert paper.results == "We found result Y."
      assert paper.conclusions == "We conclude Z."
      assert paper.keywords =~ "AI"
    end

    test "propagates LLM errors" do
      llm_fn = fn _prompt -> {:error, :api_down} end

      context = %{idea: "x", methodology: "y", results: "z", literature: "w"}
      {:error, {:title_abstract_failed, :api_down}} = Paper.synthesize(context, llm_fn)
    end
  end

  describe "to_latex/1" do
    test "renders LaTeX document" do
      paper = %{
        title: "My Paper",
        abstract: "Abstract text",
        introduction: "Intro text",
        methods: "Methods text",
        results: "Results text",
        conclusions: "Conclusions text",
        keywords: "AI, ML",
        bibliography: []
      }

      latex = Paper.to_latex(paper)
      assert latex =~ "\\documentclass{article}"
      assert latex =~ "\\title{My Paper}"
      assert latex =~ "Abstract text"
      assert latex =~ "\\section{Introduction}"
      assert latex =~ "\\section{Results}"
    end
  end

  describe "generate_bibliography/1" do
    test "generates BibTeX entries" do
      sources = [
        %{
          paper_id: "abc123",
          title: "Test Paper",
          authors: ["Alice", "Bob"],
          year: 2024,
          url: "https://example.com"
        }
      ]

      bib = Paper.generate_bibliography(sources)
      assert bib =~ "@article{abc123"
      assert bib =~ "Test Paper"
      assert bib =~ "Alice and Bob"
    end
  end
end

defmodule Vaos.Ledger.Research.PipelineNewTest do
  use ExUnit.Case

  alias Vaos.Ledger.Research.Pipeline
  alias Vaos.Ledger.Epistemic.{Ledger, Models}

  setup do
    if pid = GenServer.whereis(Ledger) do
      GenServer.stop(pid)
    end

    path = Path.join(System.tmp_dir!(), "pipeline_new_test_#{:rand.uniform(999999)}.json")
    {:ok, _pid} = Ledger.start_link(path: path)

    on_exit(fn ->
      try do
        if pid = GenServer.whereis(Ledger), do: GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end

      File.rm(path)
    end)

    %{path: path}
  end

  describe "generate_idea/3 with llm_fn" do
    test "uses LLM to generate hypothesis" do
      llm_fn = fn _prompt ->
        {:ok,
         "TITLE: Novel Approach to X\n\nIDEA: We propose using technique A to solve problem B\n\nRATIONALE: This fills a gap in the literature"}
      end

      {:ok, hypothesis} = Pipeline.generate_idea(Ledger, "Study problem B", llm_fn)
      assert hypothesis.title == "Novel Approach to X"
      assert hypothesis.statement =~ "technique A"
      assert hypothesis.rationale =~ "gap"
    end
  end

  describe "develop_method/3 with llm_fn" do
    test "uses LLM to develop methodology" do
      llm_fn = fn _prompt ->
        {:ok, "Step 1: Collect data\nStep 2: Apply algorithm\nStep 3: Evaluate results"}
      end

      hyp = Models.InnovationHypothesis.new(title: "Test", statement: "Test idea")
      {:ok, method} = Pipeline.develop_method(Ledger, hyp, llm_fn)
      assert method.kind == :method
      assert method.content =~ "Collect data"
    end
  end

  describe "literature_search/3" do
    test "searches and ranks papers" do
      http_fn = fn _url, _opts ->
        {:ok,
         %{
           "data" => [
             %{
               "paperId" => "p1",
               "title" => "Relevant Paper",
               "authors" => [%{"name" => "Researcher"}],
               "year" => 2024,
               "abstract" => "This paper studies the problem",
               "url" => "https://example.com",
               "citationCount" => 10
             }
           ]
         }}
      end

      {:ok, result} = Pipeline.literature_search("study the problem", http_fn)
      assert result.literature =~ "Relevant Paper"
      assert length(result.sources) == 1
    end
  end

  describe "run/1 full pipeline with callbacks" do
    test "runs all stages with mock callbacks" do
      llm_fn = fn prompt ->
        cond do
          String.contains?(prompt, "groundbreaking idea") ->
            {:ok,
             "TITLE: Test Idea\n\nIDEA: Investigate pattern X\n\nRATIONALE: Novel approach"}

          String.contains?(prompt, "methods") ->
            {:ok, "Use regression analysis on dataset Y"}

          String.contains?(prompt, "search query") ->
            {:ok, "pattern recognition regression"}

          String.contains?(prompt, "experiment") ->
            {:ok, "print('accuracy: 0.95')"}

          String.contains?(prompt, "title and abstract") ->
            {:ok, "TITLE: Pattern X Analysis\n\nABSTRACT: We studied pattern X."}

          String.contains?(prompt, "Introduction") ->
            {:ok, "Pattern recognition is important."}

          String.contains?(prompt, "Methods") ->
            {:ok, "We used regression."}

          String.contains?(prompt, "Results") ->
            {:ok, "Accuracy was 0.95."}

          String.contains?(prompt, "Conclusions") ->
            {:ok, "Pattern X is significant."}

          String.contains?(prompt, "keywords") ->
            {:ok, "patterns, regression, analysis"}

          true ->
            {:ok, "response"}
        end
      end

      http_fn = fn _url, _opts ->
        {:ok,
         %{
           "data" => [
             %{
               "paperId" => "p1",
               "title" => "Related Work",
               "authors" => [%{"name" => "Author"}],
               "year" => 2024,
               "abstract" => "Related abstract",
               "url" => "https://example.com",
               "citationCount" => 5
             }
           ]
         }}
      end

      code_fn = fn _code, _opts ->
        {:ok, %{stdout: "accuracy: 0.95\nprecision: 0.92", stderr: ""}}
      end

      {:ok, state} =
        Pipeline.run(
          ledger: Ledger,
          llm_fn: llm_fn,
          http_fn: http_fn,
          code_fn: code_fn,
          input: "Study pattern X in dataset Y"
        )

      assert state.status == :completed
      assert state.stage == :paper
      assert state.research.idea != ""
      assert state.research.methodology != ""
      assert state.research.literature =~ "Related Work"
      assert state.research.results =~ "accuracy"
      assert state.research.paper != nil
      assert state.research.paper.title != ""
    end

    test "runs pipeline without optional callbacks" do
      llm_fn = fn prompt ->
        cond do
          String.contains?(prompt, "groundbreaking idea") ->
            {:ok, "TITLE: Minimal Test\n\nIDEA: Simple idea\n\nRATIONALE: Quick test"}

          String.contains?(prompt, "methods") ->
            {:ok, "Simple method"}

          String.contains?(prompt, "title and abstract") ->
            {:ok, "TITLE: Minimal Paper\n\nABSTRACT: Minimal abstract"}

          true ->
            {:ok, "section content"}
        end
      end

      {:ok, state} =
        Pipeline.run(
          ledger: Ledger,
          llm_fn: llm_fn,
          input: "Simple research topic"
        )

      assert state.status == :completed
    end
  end
end

defmodule Tesla.Adapter.TestCase do
  @httpbin_url "http://localhost:#{Application.get_env(:httparrot, :http_port)}"

  def httpbin_url, do: @httpbin_url
end

defmodule Tesla.Adapter.TestCase.Basic do
  defmacro __using__([adapter: adapter]) do
    quote do
      defmodule B.Client do
        use Tesla

        adapter unquote(adapter)
      end

      import Tesla.Adapter.TestCase, only: [httpbin_url: 0]
      require Tesla

      setup do
        {adapter, _} = B.Client.__adapter__
        {:ok, adapter: adapter}
      end

      test "basic head request" do
        response = B.Client.head("#{httpbin_url}/ip")
        assert response.status == 200
      end

      test "basic get request" do
        response = B.Client.get("#{httpbin_url}/ip")
        assert response.status == 200
      end

      test "basic post request" do
        response = B.Client.post("#{httpbin_url}/post", "some-post-data", headers: %{"Content-Type" => "text/plain"})
        assert response.status == 200
        assert response.headers["Content-Type"] == "application/json"
        assert Regex.match?(~r/some-post-data/, response.body)
      end

      test "passing query params" do
        client = Tesla.build_client([{Tesla.Middleware.JSON, nil}])
        response = client |> B.Client.get("#{httpbin_url}/get", query: [
          page: 1, sort: "desc",
          status: ["a", "b", "c"],
          user: [name: "Jon", age: 20]
        ])

        args = response.body["args"]

        assert args["page"] == "1"
        assert args["sort"] == "desc"
        assert args["status[]"]   == ["a", "b", "c"]
        assert args["user[name]"] == "Jon"
        assert args["user[age]"]  == "20"
      end

      test "error: normalized connection refused error", %{adapter: adapter} do
        assert {:error, :econnrefused} == adapter.call(%Tesla.Env{url: "http://localhost:1234"}, [])
      end

      test "error: connection refused" do
        assert_raise Tesla.Error, fn ->
          response = B.Client.get("http://localhost:1234")
        end
      end
    end
  end
end

defmodule Tesla.Adapter.TestCase.StreamRequestBody do
  defmacro __using__([adapter: adapter]) do
    quote do
      defmodule ReqStream.Client do
        use Tesla

        adapter unquote(adapter)
      end

      import Tesla.Adapter.TestCase, only: [httpbin_url: 0]

      test "stream request body: Stream.map" do
        body = (1..5) |> Stream.map(&to_string/1)
        response = ReqStream.Client.post("#{httpbin_url}/post", body, headers: %{"Content-Type" => "text/plain"})
        assert response.status == 200
        assert Regex.match?(~r/12345/, to_string(response.body))
      end

      test "stream request body: Stream.unfold" do
        body = Stream.unfold(5, fn 0 -> nil; n -> {n,n-1} end)
        |> Stream.map(&to_string/1)
        response = ReqStream.Client.post("#{httpbin_url}/post", body, headers: %{"Content-Type" => "text/plain"})

        assert response.status == 200
        assert Regex.match?(~r/54321/, to_string(response.body))
      end
    end
  end
end

defmodule Tesla.Adapter.TestCase.StreamResponseBody do
  defmacro __using__([adapter: adapter]) do
    quote do
      defmodule ResStream.Client do
        use Tesla

        plug Tesla.Middleware.Opts, stream_response: true

        adapter unquote(adapter)
      end

      import Tesla.Adapter.TestCase, only: [httpbin_url: 0]

      test "stream response body" do
        body = (1..100) |> Enum.map(&to_string/1) |> Enum.join
        response = ResStream.Client.post("#{httpbin_url}/post", body, headers: %{"Content-Type" => "text/plain"})
        assert response.status == 200
        assert response.body |> Enum.join |> String.contains?(body)
      end
    end
  end
end

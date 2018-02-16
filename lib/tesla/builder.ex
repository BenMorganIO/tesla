defmodule Tesla.Builder do
  defmacro __using__(opts \\ []) do
    opts = Macro.prewalk(opts, &Macro.expand(&1, __CALLER__))

    quote do
      Module.register_attribute(__MODULE__, :__middleware__, accumulate: true)
      Module.register_attribute(__MODULE__, :__adapter__, [])

      unquote(generate_request(opts))
      unquote(generate_methods(opts))

      import Tesla.Builder, only: [plug: 1, plug: 2, adapter: 1, adapter: 2]
      @before_compile Tesla.Builder
    end
  end

  @doc """
  Attach middleware to your API client

  ```ex
  defmodule ExampleApi do
    use Tesla

    # plug middleware module with options
    plug Tesla.Middleware.BaseUrl, "http://api.example.com"

    # or without options
    plug Tesla.Middleware.JSON

    # or a custom middleware
    plug MyProject.CustomMiddleware
  end
  """

  defmacro plug(middleware, opts) do
    quote do
      @__middleware__ {
        {unquote(Macro.escape(middleware)), unquote(Macro.escape(opts))},
        {:middleware, unquote(Macro.escape(__CALLER__))}
      }
    end
  end

  defmacro plug(middleware) do
    quote do
      @__middleware__ {
        unquote(Macro.escape(middleware)),
        {:middleware, unquote(Macro.escape(__CALLER__))}
      }
    end
  end

  @doc """
  Choose adapter for your API client

  ```ex
  defmodule ExampleApi do
    use Tesla

    # set adapter as module
    adapter Tesla.Adapter.Hackney

    # set adapter as anonymous function
    adapter fn env ->
      ...
      env
    end
  end
  """
  defmacro adapter(name, opts) do
    quote do
      @__adapter__ {
        {unquote(Macro.escape(name)), unquote(Macro.escape(opts))},
        {:adapter, unquote(Macro.escape(__CALLER__))}
      }
    end
  end

  defmacro adapter(name) do
    quote do
      @__adapter__ {
        unquote(Macro.escape(name)),
        {:adapter, unquote(Macro.escape(__CALLER__))}
      }
    end
  end

  @templates [
    {
      ~w(head get delete trace options)a,
      [
        [:client, :url, :options],
        [:client, :url],
        [:url, :options],
        [:url]
      ]
    },
    {
      ~w(post put patch)a,
      [
        [:client, :url, :body, :options],
        [:client, :url, :body],
        [:url, :body, :options],
        [:url, :body]
      ]
    }
  ]

  @templates [
    {
      ~w(head get delete trace options)a,
      [:url]
    },
    {
      ~w(post put patch)a,
      [:url, :body]
    }
  ]
  @variants_client [[:client], []]
  @variants_options [[:options], []]
  @methods @templates |> Enum.map(&elem(&1, 0)) |> List.flatten()

  defp generate_request(opts) do
    docs = Keyword.get(opts, :docs, true)
    for variant <- @variants_client do
      [
        generate_doc(:request, variant, docs),
        generate_fun(:request, variant)
      ]
    end
  end

  defp generate_methods(opts) do
    docs = Keyword.get(opts, :docs, true)
    only = Keyword.get(opts, :only, @methods)
    except = Keyword.get(opts, :except, [])

    for {methods, args} <- @templates,
        method <- methods,
        method in only && not (method in except),
        client <- @variants_client,
        options <- @variants_options do
      inputs = client ++ args ++ options
      [
        generate_doc(method, inputs, docs),
        generate_fun(method, inputs)
      ]
    end
  end

  def generate_fun(method, [:client, :url, :options]) do
    quote do
      def unquote(method)(%Tesla.Client{} = client, url, options) when is_list(options) do
        request(client, [method: unquote(method), url: url] ++ options)
      end
      # fallback to keep backward compatibility
      def unquote(method)(fun, url, options) when is_function(fun) and is_list(options) do
        Tesla.Migration.client_function!()
      end
    end
  end

  def generate_fun(method, [:client, :url]) do
    quote do
      def unquote(method)(%Tesla.Client{} = client, url) do
        request(client, method: unquote(method), url: url)
      end
      # fallback to keep backward compatibility
      def unquote(method)(fun, url) when is_function(fun) do
        Tesla.Migration.client_function!()
      end
    end
  end

  def generate_fun(method, [:url, :options]) do
    quote do
      def unquote(method)(url, options) when is_list(options) do
        request([method: unquote(method), url: url] ++ options)
      end
    end
  end

  def generate_fun(method, [:url]) do
    quote do
      def unquote(method)(url) do
        request(method: unquote(method), url: url)
      end
    end
  end

  def generate_fun(method, [:client, :url, :body, :options]) do
    quote do
      def unquote(method)(%Tesla.Client{} = client, url, body, options) when is_list(options) do
        request(client, [method: unquote(method), url: url, body: body] ++ options)
      end
      # fallback to keep backward compatibility
      def unquote(method)(fun, url, body, options) when is_function(fun) and is_list(options) do
        Tesla.Migration.client_function!()
      end
    end
  end

  def generate_fun(method, [:client, :url, :body]) do
    quote do
      def unquote(method)(%Tesla.Client{} = client, url, body) do
        request(client, method: unquote(method), url: url, body: body)
      end
      # fallback to keep backward compatibility
      def unquote(method)(fun, url, body) when is_function(fun) do
        Tesla.Migration.client_function!()
      end
    end
  end

  def generate_fun(method, [:url, :body, :options]) do
    quote do
      def unquote(method)(url, body, options) when is_list(options) do
        request([method: unquote(method), url: url, body: body] ++ options)
      end
    end
  end

  def generate_fun(method, [:url, :body]) do
    quote do
      def unquote(method)(url, body) do
        request(method: unquote(method), url: url, body: body)
      end
    end
  end

  def generate_fun(:request, [:client]) do
    quote do
      def request(%Tesla.Client{} = client, options) when is_list(options) do
        Tesla.execute(__MODULE__, client, options)
      end
    end
  end

  def generate_fun(:request, []) do
    quote do
      def request(options) when is_list(options) do
        Tesla.execute(__MODULE__, %Tesla.Client{}, options)
      end
    end
  end

  def generate_doc(method, variant, true), do: generate_doc(method, variant)

  def generate_doc(_, _, false) do
    quote do: @doc false
  end

  def generate_doc(method, [:client, :url, :options]) do
    quote do
      @doc """
      Perform a #{unquote(method |> to_string |> String.upcase())} request.
      See `request/1` or `request/2` for options definition.

      Example
          myclient |> ExampleApi.#{unquote(method)}("/users", query: [scope: "admin"])
      """
      @spec unquote(method)(Tesla.Env.client(), Tesla.Env.url(), [option]) :: Tesla.Env.t()
    end
  end

  def generate_doc(method, [:client, :url]) do
    quote do
      @doc """
      Perform a #{unquote(method |> to_string |> String.upcase())} request.
      See `request/1` or `request/2` for options definition.

      Example
          myclient |> ExampleApi.#{unquote(method)}("/users")
          # or
          ExampleApi.#{unquote(method)}("/users", query: [page: 1])
      """
      @spec unquote(method)(Tesla.Env.client(), Tesla.Env.url()) :: Tesla.Env.t()
    end
  end

  def generate_doc(method, [:url, :options]) do
    quote do
      @spec unquote(method)(Tesla.Env.url(), [option]) :: Tesla.Env.t()
    end
  end

  def generate_doc(method, [:url, ]) do
    quote do
      @doc """
      Perform a #{unquote(method |> to_string |> String.upcase())} request.
      See `request/1` or `request/2` for options definition.

      Example
          ExampleApi.#{unquote(method)}("/users")
      """
      @spec unquote(method)(Tesla.Env.url()) :: Tesla.Env.t()
    end
  end

  def generate_doc(method, [:client, :url, :body, :options]) do
    quote do
      @doc """
      Perform a #{unquote(method |> to_string |> String.upcase())} request.
      See `request/1` or `request/2` for options definition.

      Example
          myclient |> ExampleApi.#{unquote(method)}("/users", %{name: "Jon"}, query: [scope: "admin"])
      """
      @spec unquote(method)(Tesla.Env.client(), Tesla.Env.url(), Tesla.Env.body(), [option]) :: Tesla.Env.t()
    end
  end

  def generate_doc(method, [:client, :url, :body]) do
    quote do
      @doc """
      Perform a #{unquote(method |> to_string |> String.upcase())} request.
      See `request/1` or `request/2` for options definition.

      Example
          myclient |> ExampleApi.#{unquote(method)}("/users", %{name: "Jon"})
          # or
          ExampleApi.#{unquote(method)}("/users", %{name: "Jon"}, query: [scope: "admin"])
      """
      @spec unquote(method)(Tesla.Env.client(), Tesla.Env.url(), Tesla.Env.body()) :: Tesla.Env.t()
    end
  end

  def generate_doc(method, [:url, :body, :options]) do
    quote do
      @spec unquote(method)(Tesla.Env.url(), Tesla.Env.body(), [option]) :: Tesla.Env.t()
    end
  end

  def generate_doc(method, [:url, :body]) do
    quote do
      @doc """
      Perform a #{unquote(method |> to_string |> String.upcase())} request.
      See `request/1` or `request/2` for options definition.

      Example
          ExampleApi.#{unquote(method)}("/users", %{name: "Jon"})
      """
      @spec unquote(method)(Tesla.Env.url(), Tesla.Env.body()) :: Tesla.Env.t()
    end
  end

  def generate_doc(:request, [:client]) do
    quote do
      @type option ::
              {:method, Tesla.Env.method()}
              | {:url, Tesla.Env.url()}
              | {:query, Tesla.Env.query()}
              | {:headers, Tesla.Env.headers()}
              | {:body, Tesla.Env.body()}
              | {:opts, Tesla.Env.opts()}

      @doc """
      Perform a request using client function

      Options:
      - `:method`   - the request method, one of [:head, :get, :delete, :trace, :options, :post, :put, :patch]
      - `:url`      - either full url e.g. "http://example.com/some/path" or just "/some/path" if using `Tesla.Middleware.BaseUrl`
      - `:query`    - a keyword list of query params, e.g. `[page: 1, per_page: 100]`
      - `:headers`  - a keyworld list of headers, e.g. `[{"content-type", "text/plain"}]`
      - `:body`     - depends on used middleware:
          - by default it can be a binary
          - if using e.g. JSON encoding middleware it can be a nested map
          - if adapter supports it it can be a Stream with any of the above
      - `:opts`     - custom, per-request middleware or adapter options

      Examples:

          ExampleApi.request(method: :get, url: "/users/path")

      You can also use shortcut methods like:

          ExampleApi.get("/users/1")

      or

          myclient |> ExampleApi.post("/users", %{name: "Jon"})
      """
      @spec request(Tesla.Env.client(), [option]) :: Tesla.Env.t()
    end
  end

  def generate_doc(:request, []) do
    quote do
      @doc """
      Perform a request. See `request/2` for available options.
      """
      @spec request([option]) :: Tesla.Env.t()
    end
  end

  defmacro __before_compile__(env) do
    Tesla.Migration.breaking_alias_in_config!(env.module)

    adapter =
      env.module
      |> Module.get_attribute(:__adapter__)
      |> compile()

    middleware =
      env.module
      |> Module.get_attribute(:__middleware__)
      |> Enum.reverse()
      |> compile()

    quote do
      def __middleware__, do: unquote(middleware)
      def __adapter__, do: unquote(adapter)
    end
  end

  defmacro client(pre, post) do
    context = {:middleware, __CALLER__}

    quote do
      %Tesla.Client{
        pre: unquote(compile_context(pre, context)),
        post: unquote(compile_context(post, context))
      }
    end
  end

  defp compile(nil), do: nil
  defp compile(list) when is_list(list), do: Enum.map(list, &compile/1)

  # {Tesla.Middleware.Something, opts}
  defp compile({{{:__aliases__, _, _} = ast_mod, ast_opts}, {_kind, caller}}) do
    Tesla.Migration.breaking_headers_map!(ast_mod, ast_opts, caller)
    quote do: {unquote(ast_mod), :call, [unquote(ast_opts)]}
  end

  # :local_middleware, opts
  defp compile({{name, _opts}, {kind, caller}}) when is_atom(name) do
    Tesla.Migration.breaking_alias!(kind, name, caller)
  end

  # Tesla.Middleware.Something
  defp compile({{:__aliases__, _, _} = ast_mod, {_kind, _caller}}) do
    quote do: {unquote(ast_mod), :call, [nil]}
  end

  # fn env -> ... end
  defp compile({{:fn, _, _} = ast_fun, {_kind, _caller}}) do
    quote do: {:fn, unquote(ast_fun)}
  end

  # :local_middleware
  defp compile({name, {kind, caller}}) when is_atom(name) do
    Tesla.Migration.breaking_alias!(kind, name, caller)
  end

  defp compile_context(list, context) do
    list
    |> Enum.map(&{&1, context})
    |> compile()
  end
end

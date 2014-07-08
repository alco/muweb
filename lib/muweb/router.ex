defmodule Muweb.Router do
  @moduledoc """
  Router definition that provides the routing DSL for user modules.

  See the docs for `Muweb.Router.Mixin` for a detailed overview of the
  provided functions.

  ## Example

      defmodule MyRouter do
        use Muweb.Router

        # serve the current working directory
        handle _, :get, &static_handler
      end

  """

  @doc false
  defmacro __using__(_) do
    quote do
      @before_compile unquote(__MODULE__)
      import Muweb.Router.Mixin
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      def init(opts) do
        {__MODULE__, opts}
      end
    end
  end
end


defmodule Muweb.Router.Mixin do
  @moduledoc """
  Muweb.Router.Mixin implements the routing DSL.

  You generally include use it as follows:

      defmodule MyRouter do
        use Muweb.Router

        handle _, :get, &static_handler
      end

  """

  @doc """
  Autodefined function the creates an instance of the router to pass to the
  server.
  """
  def init(opts)

  @doc """
  Autodefined function that check if any of the handlers defined within the
  router match the given path.
  """
  def match?(path)


  @doc """
  Macro that can be used instead of a handler to turn an existing function
  (that is unaware of the HTTP context it is being used in) into a handler.

  The `opts` argument is optional.
  """
  def wrap(function, arguments, opts)


  @doc """
  Retrieve the named parameter from the initial value passed to the user
  router module's `init/1` function.

  ## Example

      defmodule MyRouter do
        use Muweb.Router

        handle _, :get, &static_handler, root: param(:root_dir)
      end

      MyRouter.init(root_dir: "...")

  """
  defmacro param(name) when is_atom(name) do
    quote do: var!(_init_opts)[unquote(name)]
  end


  @doc """
  Mount another router at the specified path.

  All requests starting with that path will be forwarded to the mounter router.
  If no handler within that router matches the request, it will continue to
  check the remaining handlers in the current router.

  The mounted router should match paths starting from the root. The `path`
  argument passed to the `mount` macro will determine the actual path for the
  mounted router to use.

  ## Example

      defmodule APIRouter do
        use Muweb.Router

        handle "/hello", :get do
          reply(200, "hi")
        end
      end


      defmodule MyRouter do
        use Muweb.Router

        mount "/api", APIRouter
      end

      APIRouter.match?("/hello")
      #=> true

      MyRouter.match?("/api/hello")
      #=> true

  """
  defmacro mount(path, module, opts \\ [])

  defmacro mount(path, module, opts)
    when is_binary(path) and is_atom(module) and is_list(opts),
    do: do_mount(path, module, opts)

  defmacro mount(path, {:__aliases__, _, _}=module, opts)
    when is_binary(path) and is_list(opts),
    do: do_mount(path, module, opts)


  defp do_mount(path, module, _opts) do
    components = path_components(path)
    q = quote do
      def handle(method, [unquote_splicing(components) | rest], req, init_opts) do
        unquote(module).handle(method, rest, req, init_opts)
      end
    end
    #q |> Macro.to_string |> IO.puts
    q
  end


  @doc """
  Define a handler for the given path and method combination.

  Accepts one method or a list of methods.

  There are two forms of this macro:

   * `handle(path, methods, handler, opts \\ [])`
   * `handle(path, methods, opts \\ [], do_block)`

  In the first form, `handler` can be a function or a wrapped function (see
  `wrap/3`).

  The second form expects a do-block that implements the handler inline.

  ## Example

      defmodule MyRouter do
        use Muweb.Router

        handle "/", [:get, :head], &static_handler, file: "index.html"
        handle "/secret", :post, wrap(Utill.store_secret, [])

        handle "/home", :get do
          reply(200, "Welcome")
        end
      end

  """
  defmacro handle(path, methods, handler_or_do_block)

  defmacro handle(path, method, {:&, _, _}=func),
    do: do_handle(path, method, {:func, func}, [], __CALLER__.module)

  defmacro handle(path, method, [do: code]),
    do: do_handle(path, method, {:code, code}, [], __CALLER__.module)

  defmacro handle(path, method, {:wrap, _, args}),
    do: do_handle(path, method, {:wrap, args}, [], __CALLER__.module)


  @doc """
  A form of the `handle` macro that also takes a list of options. See
  `handle/3` for the full description.
  """
  defmacro handle(path, methods, _, _)

  defmacro handle(path, method, {:&, _, _}=func, opts)
    when is_list(opts),
    do: do_handle(path, method, {:func, func}, opts, __CALLER__.module)

  defmacro handle(path, method, opts, [do: code])
    when is_list(opts),
    do: do_handle(path, method, {:code, code}, opts, __CALLER__.module)

  defmacro handle(path, method, {:wrap, _, args}, opts),
    do: do_handle(path, method, {:wrap, args}, opts, __CALLER__.module)

  ###

  defp do_handle(path, method, handler, opts, caller) do
    methods = List.wrap(method)
    matchspec = path_to_matchspec(path, caller) |> quote_matchspec()

    quoted_body = quote_handler(handler, opts)

    quoted_head = if match?({:_, _, nil}, method) do
      quote do: handle(_, unquote(matchspec), var!(req), var!(_init_opts))
    else
      quote do: handle(method, unquote(matchspec), var!(req), var!(_init_opts)) when method in unquote(methods)
    end

    q = quote do
      def unquote(quoted_head) do
        unquote(quoted_body)
      end
    end
    #q |> Macro.to_string |> IO.puts
    q
  end


  defp path_components(path) do
    String.split(path, "/")
    |> Muweb.Util.strip_list()
  end


  defp path_to_matchspec(path, context) when is_binary(path) do
    components =
      path_components(path)
      |> Enum.map(fn
        ":" <> name -> {String.to_atom(name), [], context}
        other       -> other
      end)

    reversed = Enum.reverse(components)
    if reversed != [] and hd(reversed) == "..." do
      {:glob, tl(reversed) |> Enum.reverse()}
    else
      components
    end
  end

  defp path_to_matchspec(path, _) when is_list(path) do
    path
  end

  defp path_to_matchspec({:_, _, nil}=path, _) do
    path
  end


  defp quote_matchspec(spec) do
    case spec do
      {:_, _, nil}  -> quote do: path
      {:glob, list} -> quote do: [unquote_splicing(list) | _]=path
      other         -> quote do: unquote(other)=path
    end
  end


  defp quote_handler(handler, opts) do
    case handler do
      {:func, {:&, meta, [arg]}} ->
        func = {:&, meta, [{:/, meta, [arg, 3]}]}
        quote do: unquote(func).(path, unquote(opts), var!(req))

      {:wrap, [{fun, _, _}, arguments]} ->
        wrap_fun(fun, arguments, [])

      {:wrap, [{fun, _, _}, arguments, opts]} ->
        wrap_fun(fun, arguments, opts)

      {:code, code} ->
        quote do
          import Muweb.Handler
          unquote(code)
        end
    end
  end

  defp wrap_fun(fun, args, opts) do
    funcall = {fun, [], args}
    quote do
      import Muweb.Handler
      val = unquote(funcall)
      ireply(unquote(opts[:status] || 200), to_string(val))
    end
  end
end

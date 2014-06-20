defmodule Muweb.Handler do
  @proto_version "1.1"

  defmacro __using__(_) do
    quote do
      #import Kernel, except: [def: 2]
      import unquote(__MODULE__), only: :macros
    end
  end


  defmacro reply(status) do
    quote do
      unquote(__MODULE__).reply(unquote(status), nil, [], var!(conn), var!(req))
    end
  end

  defmacro reply(status, data) do
    quote do
      unquote(__MODULE__).reply(unquote(status), unquote(data), [], var!(conn), var!(req))
    end
  end

  defmacro reply(status, data, opts) do
    quote do
      unquote(__MODULE__).reply(unquote(status), unquote(data), unquote(opts), var!(conn), var!(req))
    end
  end

  defmacro reply_file(status, path, opts \\ []) do
    quote do
      unquote(__MODULE__).reply_file(unquote(status), unquote(path), unquote(opts), var!(conn), var!(req))
    end
  end

  defmacro abort() do
    quote do
      unquote(__MODULE__).close_connection(var!(conn))
    end
  end

  defmacro query(key, default \\ nil) do
    quote do
      Map.get(URI.decode_query(var!(req).query), unquote(key), unquote(default))
    end
  end

  defmacro req() do
    quote do: var!(req)
  end

  def close_connection(_conn) do
    :noreply
  end

  def reply(status, data, opts, conn, req) do
    headers = opts[:headers] || %{}
    if data && !Map.get(headers, "content-length") do
      headers = Map.put(headers, "content-length", byte_size(data))
    end
    if req().method == :head do
      data = nil
    end
    reply_http(conn, status, headers, data)
  end

  def reply_file(status, path, opts, conn, req) do
    headers = opts[:headers] || %{}
    {status, data} = case File.stat(path) do
      {:error, :enoent} -> {404, "Not Found"}
      {:ok, %File.Stat{type: :directory}} -> {404, "Not Found"}

      {:ok, %File.Stat{size: size}} ->
        if req().method != :head do
          data = File.read!(path)
        end
        if !Map.get(headers, "content-length") do
          headers = Map.put(headers, "content-length", size)
        end
        {status, data}
    end
    if req().method == :head do
      data = nil
    end
    reply_http(conn, status, headers, data)
  end


  #defmacro def({:handle, _, args}, [do: code]) do
    #quote do
      #def handle(unquote_splicing(args), var!(conn, __MODULE__)) do
        #unquote(code)
      #end
    #end
  #end


  defp reply_http(conn, status, headers, data) do
    import Kernel, except: [send: 2]
    import Muweb.Server, only: [send: 2]

    status_string = "HTTP/#{@proto_version} #{symbolic_status(status)}"

    send(conn, status_string <> "\r\n")
    Enum.each(headers, fn {name, value} ->
      send(conn, "#{name}: #{value}\r\n")
    end)
    send(conn, "\r\n")
    if data, do: send(conn, data)
    :noreply
  end


  @status_mapping [
    # 1xx Informational
   #{100, "Continue"},
   #{101, "Switching Protocols"},

    # 2xx Success
    {200, "OK"},
    {201, "Created"},
    {202, "Accepted"},
   #{203, "Non-Authoritative Information"},    # since HTTP/1.1
    {204, "No Content"},
   #{205, "Reset Content"},
   #{206, "Partial Content"},

    # 3xx Redirection
    {300, "Multiple Choices"},
    {301, "Moved Permanently"},
    {302, "Found"},
    {303, "See Other"},                        # since HTTP/1.1
    {304, "Not Modified"},
   #{305, "Use Proxy"},                        # since HTTP/1.1
    {307, "Temporary Redirect"},               # since HTTP/1.1
    {308, "Permanent Redirect"},               # approved as experimental RFC

    # 4xx Client Error
    {400, "Bad Request"},
   #{401, "Unauthorized"},
   #{402, "Payment Required"},
    {403, "Forbidden"},
    {404, "Not Found"},
    {405, "Method Not Allowed"},
    {406, "Not Acceptable"},
   #{407, "Proxy Authentication Required"},
   #{408, "Request Timeout"},
   #{409, "Conflict"},
   #{410, "Gone"},
   #{411, "Length Required"},
   #{412, "Precondition Failed"},
   #{413, "Request Entity Too Large"},
   #{414, "Request-URI Too Long"},
   #{415, "Unsupported Media Type"},
   #{416, "Requested Range Not Satisfiable"},
   #{417, "Expectation Failed"},
   {418, "I'm a teapot"},                     # RFC 2324
   #{419, "Authentication Timeout"},           # not in RFC 2616
   #{426, "Upgrade Required"},                 # RFC 2817
   #{428, "Precondition Required"},            # RFC 6585
   #{429, "Too Many Requests"},                # RFC 6585
   #{431, "Request Header Fields Too Large"},  # RFC 6585

    # 5xx Server Error
    {500, "Internal Server Error"},
    {501, "Not Implemented"},
   #{502, "Bad Gateway"},
    {503, "Service Unavailable"},
   #{504, "Gateway Timeout"},
    {505, "HTTP Version Not Supported"},
   #{506, "Variant Also Negotiates"},          # RFC 2295
   #{510, "Not Extended"},                     # RFC 2774
   #{511, "Network Authentication Required"},  # RFC 6585
  ]

  for {num, string} <- @status_mapping do
    def symbolic_status(unquote(num)=n), do: "#{n} " <> unquote(string)
    def symbolic_status(unquote(string)=s), do: "#{unquote(num)} " <> s
  end

  def symbolic_status(bin) when is_binary(bin) do
    raise ArgumentError, message: 'Unsupported or invalid status #{bin}'
  end
end

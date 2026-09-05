# © 2026 aiaiaiai · aiaiaiai.org
# frozen_string_literal: true

require "socket"

# A collector that behaves badly on purpose.
#
# Real sockets rather than stubbed HTTP: the failures the SDK must survive --
# refused connections, silence, TLS mismatch, nonsense answers -- only happen
# at that level.
class StubCollector
  RESPONSES = {
    accepted: ["202 Accepted", '{"accepted":1,"events":[{"event_id":"018f0000-0000-7000-8000-000000000000"}]}'],
    unauthorized: ["401 Unauthorized", '{"error":"unauthorized"}'],
    forbidden: ["403 Forbidden", '{"error":"project_mismatch"}'],
    server_error: ["500 Internal Server Error", '{"error":"internal_error"}'],
    too_many_requests: ["429 Too Many Requests", '{"error":"slow_down"}']
  }.freeze

  attr_reader :port, :requests

  # :silent accepts the connection and never answers; :garbage answers with
  # something that is not HTTP at all.
  def initialize(mode: :accepted)
    @mode = mode
    @requests = []
    @mutex = Mutex.new
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @thread = Thread.new { serve }
    @thread.report_on_exception = false
  end

  def endpoint(scheme: "http")
    "#{scheme}://127.0.0.1:#{port}"
  end

  def received
    @mutex.synchronize { @requests.dup }
  end

  def stop
    @thread&.kill
    @server&.close
  rescue IOError
    nil
  end

  private

  def serve
    loop do
      socket = @server.accept
      handle(socket)
    end
  rescue IOError, Errno::EBADF
    nil
  end

  def handle(socket)
    request = read_request(socket)
    @mutex.synchronize { @requests << request }

    case @mode
    when :silent
      sleep 30
    when :garbage
      socket.write("\x00\x01 not http at all\r\n")
      socket.close
    else
      status, body = RESPONSES.fetch(@mode)
      socket.write("HTTP/1.1 #{status}\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      socket.close
    end
  rescue
    close(socket)
  end

  def close(socket)
    socket.close
  rescue IOError, Errno::EBADF
    nil
  end

  def read_request(socket)
    headers = +""
    headers << socket.readpartial(1) until headers.end_with?("\r\n\r\n")
    length = headers[/^content-length:\s*(\d+)/i, 1].to_i
    body = length.positive? ? socket.read(length) : ""
    {headers: headers, body: body}
  end
end

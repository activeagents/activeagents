# frozen_string_literal: true

require "socket"

# A minimal HTTP/1.1 server for exercising OllamaHostProbe end to end
# without a mocking library: it answers every request with the canned
# status and body and records the request line and headers it received.
#
#   FakeOllamaServer.run(body: { data: [ { id: "qwen3:4b" } ] }.to_json) do |server|
#     result = OllamaHostProbe.call(host: server.host)
#     assert_equal "/v1/models", server.requests.first[:path]
#   end
class FakeOllamaServer
  attr_reader :requests

  def self.run(status: 200, body: "", **options, &block)
    server = new(status: status, body: body, **options)
    server.start
    block.call(server)
  ensure
    server&.stop
  end

  def initialize(status:, body:, content_type: "application/json")
    @status = status
    @body = body
    @content_type = content_type
    @requests = []
  end

  # Base URL as a user would type it (no /v1 — the probe adds it).
  def host
    "http://127.0.0.1:#{@port}"
  end

  def start
    @socket = TCPServer.new("127.0.0.1", 0)
    @port = @socket.addr[1]
    @thread = Thread.new do
      loop do
        client = @socket.accept
        handle(client)
      rescue IOError, Errno::EBADF
        break
      end
    end
  end

  def stop
    @socket&.close
    @thread&.join(1)
  end

  private

  def handle(client)
    request_line = client.gets
    return client.close unless request_line

    method, path, = request_line.split
    headers = {}
    while (line = client.gets) && line != "\r\n"
      name, value = line.split(":", 2)
      headers[name.strip] = value.to_s.strip
    end
    @requests << { method: method, path: path, headers: headers }

    client.write(
      "HTTP/1.1 #{@status} #{@status == 200 ? 'OK' : 'Error'}\r\n" \
      "Content-Type: #{@content_type}\r\n" \
      "Content-Length: #{@body.bytesize}\r\n" \
      "Connection: close\r\n\r\n#{@body}"
    )
  ensure
    client.close
  end
end

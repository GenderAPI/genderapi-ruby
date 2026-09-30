# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "json"
require "socket"
require "minitest/autorun"
require "genderapi"

# Response examples exported from openapi-v2.json (synthetic data).
module Fixtures
  PATH = File.expand_path("fixtures/openapi_examples.json", __dir__)
  EXAMPLES = JSON.parse(File.read(PATH))["examples"].freeze

  module_function

  # @return [Hash] a deep copy of an OpenAPI example
  def get(name)
    JSON.parse(JSON.generate(EXAMPLES.fetch(name)))
  end

  # The published examples show IP-trial access; keyed tests expect API-key access.
  def keyed(name)
    body = get(name)
    body["meta"]["access"] = { "mode" => "api_key", "reason" => nil }
    body["meta"]["usage"].merge!("resets_at" => nil, "limit" => nil, "period_seconds" => nil)
    body
  end
end

# A tiny local HTTP/1.1 server: no real API, no credits, no external network.
class StubServer
  Request = Struct.new(:method, :target, :headers, :body, keyword_init: true)

  attr_reader :requests, :port

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @responses = Queue.new
    @requests = []
    @connections = 0
    @lock = Mutex.new
    @thread = Thread.new { serve }
  end

  def base_url
    "http://127.0.0.1:#{@port}/api/v2"
  end

  def connections
    @lock.synchronize { @connections }
  end

  # Queue a response: a Hash (status/headers/json/body/delay) or :close.
  def enqueue(response = nil, **opts)
    @responses << (response || opts)
  end

  def json(status, body, headers = {})
    enqueue(status: status, headers: { "Content-Type" => "application/json" }.merge(headers), body: JSON.generate(body))
  end

  def problem(status, body, headers = {})
    enqueue(status: status, headers: { "Content-Type" => "application/problem+json" }.merge(headers),
            body: JSON.generate(body))
  end

  def stop
    @thread.kill
    @server.close
  rescue IOError
    nil
  end

  private

  def serve
    loop do
      socket = @server.accept
      @lock.synchronize { @connections += 1 }
      handle(socket)
    end
  rescue IOError, Errno::EBADF
    nil
  end

  def handle(socket)
    request = read_request(socket)
    return socket.close if request.nil?

    @lock.synchronize { @requests << request }
    response = @responses.empty? ? { status: 500, body: "no stub response queued" } : @responses.pop
    return socket.close if response == :close

    sleep(response[:delay]) if response[:delay]
    body = response[:body].to_s.b
    head = +"HTTP/1.1 #{response[:status]} Stub\r\n"
    (response[:headers] || {}).each { |k, v| head << "#{k}: #{v}\r\n" }
    head << "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n"
    socket.write(head)
    socket.write(body)
    socket.close
  rescue IOError, SystemCallError
    socket.close unless socket.closed?
  end

  def read_request(socket)
    line = socket.gets("\r\n")
    return nil if line.nil?

    method, target, = line.split(" ")
    headers = {}
    while (header = socket.gets("\r\n")) && header != "\r\n"
      name, value = header.split(":", 2)
      headers[name.strip.downcase] = value.to_s.strip
    end
    length = headers["content-length"].to_i
    body = length.positive? ? socket.read(length) : nil
    Request.new(method: method, target: target, headers: headers, body: body)
  end
end

class StubTest < Minitest::Test
  KEY = "0123456789abcdef01234567"

  def setup
    @stub = StubServer.new
  end

  def teardown
    @stub.stop
  end

  def client(**opts)
    GenderAPI::Client.new(api_key: KEY, base_url: @stub.base_url, timeout: 2, **opts)
  end

  def last_request
    @stub.requests.last
  end

  def sent_json
    JSON.parse(last_request.body)
  end
end

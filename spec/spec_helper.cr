require "spec"
require "http/client"
require "socket"
require "json"

# Test configuration
LOCALHOST   = "127.0.0.1"
SMTP_PORT   = 20025
HTTP_PORT   = 20080
DEFAULT_FROM = "from@example.com"
DEFAULT_TO   = "to@example.com"

# Path to built binary (relative to spec directory)
MAILCATCHER_BIN = File.expand_path("../bin/mailcatcher", __DIR__)

# Path to example emails (in parent repo)
EXAMPLES_DIR = File.expand_path("../examples", __DIR__)

# Helper class to manage a MailCatcher process for testing
class MailCatcherProcess
  getter process : Process?
  getter http_url : String
  getter smtp_port : Int32
  getter http_port : Int32

  def initialize(@smtp_port = SMTP_PORT, @http_port = HTTP_PORT)
    @http_url = "http://#{LOCALHOST}:#{@http_port}"
    @process = nil
  end

  def start
    @process = Process.new(MAILCATCHER_BIN, [
      "--foreground",
      "--smtp-ip", LOCALHOST,
      "--smtp-port", @smtp_port.to_s,
      "--http-ip", LOCALHOST,
      "--http-port", @http_port.to_s,
    ])

    # Wait for it to boot
    wait_for_port(@smtp_port)
    wait_for_port(@http_port)
  end

  def pid : Int64?
    @process.try(&.pid.to_i64)
  end

  def stop
    if process = @process
      begin
        process.signal(Signal::TERM)
        # Wait for process to exit with timeout
        100.times do
          break if process.terminated?
          sleep 0.05.seconds
        end
      rescue RuntimeError
        # Process already exited
      end
      @process = nil
    end
  end

  def running? : Bool
    if process = @process
      !process.terminated?
    else
      false
    end
  end

  private def wait_for_port(port : Int32, timeout : Time::Span = 10.seconds)
    deadline = Time.monotonic + timeout
    loop do
      begin
        socket = TCPSocket.new(LOCALHOST, port, connect_timeout: 1.second)
        socket.close
        return
      rescue Socket::ConnectError | IO::TimeoutError
        if Time.monotonic > deadline
          raise "Timeout waiting for port #{port}"
        end
        sleep 0.1.seconds
      end
    end
  end
end

# SMTP client helper
class SmtpClient
  def initialize(@host : String = LOCALHOST, @port : Int32 = SMTP_PORT)
  end

  def deliver(message : String, from : String = DEFAULT_FROM, to : String = DEFAULT_TO)
    socket = TCPSocket.new(@host, @port)
    begin
      # Read greeting
      read_response(socket)

      # EHLO
      socket.print "EHLO localhost\r\n"
      read_response(socket)

      # MAIL FROM
      socket.print "MAIL FROM:<#{from}>\r\n"
      read_response(socket)

      # RCPT TO
      socket.print "RCPT TO:<#{to}>\r\n"
      read_response(socket)

      # DATA
      socket.print "DATA\r\n"
      read_response(socket)

      # Send message body (with dot-stuffing)
      message.each_line do |line|
        if line.starts_with?(".")
          socket.print ".#{line}\r\n"
        else
          socket.print "#{line}\r\n"
        end
      end
      socket.print ".\r\n"
      read_response(socket)

      # QUIT
      socket.print "QUIT\r\n"
      read_response(socket)
    ensure
      socket.close
    end
  end

  private def read_response(socket : TCPSocket) : String
    response = ""
    loop do
      line = socket.gets || break
      response += line + "\n"
      # Check if this is the last line (no continuation)
      break unless line.size >= 4 && line[3] == '-'
    end
    response
  end
end

# HTTP client helper
class ApiClient
  def initialize(@base_url : String = "http://#{LOCALHOST}:#{HTTP_PORT}")
  end

  def get(path : String) : HTTP::Client::Response
    HTTP::Client.get("#{@base_url}#{path}")
  end

  def delete(path : String) : HTTP::Client::Response
    HTTP::Client.delete("#{@base_url}#{path}")
  end

  def messages : Array(JSON::Any)
    response = get("/messages")
    JSON.parse(response.body).as_a
  end

  def message(id : Int64) : JSON::Any
    response = get("/messages/#{id}.json")
    JSON.parse(response.body)
  end

  def message_source(id : Int64) : String
    response = get("/messages/#{id}.source")
    response.body
  end

  def message_plain(id : Int64) : String
    response = get("/messages/#{id}.plain")
    response.body
  end

  def message_html(id : Int64) : String
    response = get("/messages/#{id}.html")
    response.body
  end

  def delete_message(id : Int64) : HTTP::Client::Response
    delete("/messages/#{id}")
  end

  def delete_all_messages : HTTP::Client::Response
    delete("/messages")
  end

  def quit : HTTP::Client::Response
    delete("/")
  end
end

# Helper to read example emails
def read_example(name : String) : String
  File.read(File.join(EXAMPLES_DIR, name))
end

# Helper to deliver example emails
def deliver_example(name : String, smtp : SmtpClient = SmtpClient.new, from : String = DEFAULT_FROM, to : String = DEFAULT_TO)
  smtp.deliver(read_example(name), from, to)
end

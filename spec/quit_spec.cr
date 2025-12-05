require "./spec_helper"

describe "MailCatcher Quit" do
  describe "DELETE / (quit via API)" do
    it "quits cleanly via the API" do
      mailcatcher = MailCatcherProcess.new
      mailcatcher.start

      # Process should be running
      mailcatcher.running?.should be_true

      # Quit via API
      api = ApiClient.new
      response = api.quit
      response.status_code.should eq(204)

      # Wait for process to exit (quit spawns a fiber that waits before exit)
      sleep 2.seconds

      # Process should have exited
      mailcatcher.running?.should be_false
    end

    it "returns 403 when --no-quit is set" do
      # Use a different port to avoid conflict with previous test
      no_quit_http_port = HTTP_PORT + 100
      no_quit_smtp_port = SMTP_PORT + 100

      # Start with custom args including --no-quit
      process = Process.new(MAILCATCHER_BIN, [
        "--foreground",
        "--smtp-ip", LOCALHOST,
        "--smtp-port", no_quit_smtp_port.to_s,
        "--http-ip", LOCALHOST,
        "--http-port", no_quit_http_port.to_s,
        "--no-quit",
      ])

      # Wait for it to boot (poll for port)
      deadline = Time.monotonic + 10.seconds
      loop do
        begin
          socket = TCPSocket.new(LOCALHOST, no_quit_http_port, connect_timeout: 1.second)
          socket.close
          break
        rescue Socket::ConnectError | IO::TimeoutError
          if Time.monotonic > deadline
            raise "Timeout waiting for server to start"
          end
          sleep 0.1.seconds
        end
      end

      begin
        # Try to quit via API
        api = ApiClient.new("http://#{LOCALHOST}:#{no_quit_http_port}")
        response = api.quit
        response.status_code.should eq(403)
        response.body.should contain("Quit is disabled")

        # Process should still be running
        process.terminated?.should be_false
      ensure
        # Clean up
        begin
          process.signal(Signal::TERM)
          # Wait for termination
          50.times do
            break if process.terminated?
            sleep 0.1.seconds
          end
        rescue RuntimeError
          # Already exited
        end
      end
    end
  end

  describe "SIGINT (Ctrl+C)" do
    it "quits cleanly on SIGINT" do
      mailcatcher = MailCatcherProcess.new
      mailcatcher.start

      # Process should be running
      mailcatcher.running?.should be_true

      # Get the process
      process = mailcatcher.process.not_nil!

      # Send SIGINT
      process.signal(Signal::INT)

      # Wait for process to exit
      sleep 0.5.seconds

      # Process should have exited
      mailcatcher.running?.should be_false
    end
  end

  describe "SIGTERM" do
    it "quits cleanly on SIGTERM" do
      mailcatcher = MailCatcherProcess.new
      mailcatcher.start

      # Process should be running
      mailcatcher.running?.should be_true

      # Get the process
      process = mailcatcher.process.not_nil!

      # Send SIGTERM
      process.signal(Signal::TERM)

      # Wait for process to exit (quit spawns a fiber that waits before exit)
      sleep 2.seconds

      # Process should have exited
      mailcatcher.running?.should be_false
    end
  end
end

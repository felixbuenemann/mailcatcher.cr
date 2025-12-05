require "./spec_helper"

describe "CatchMail" do
  mailcatcher = MailCatcherProcess.new
  api = ApiClient.new

  before_each do
    mailcatcher.start
  end

  after_each do
    mailcatcher.stop
  end

  describe "--help" do
    it "shows catchmail help when invoked as subcommand" do
      output = `#{MAILCATCHER_BIN} catchmail --help 2>&1`
      status = $?

      output.should contain("Usage: catchmail")
      output.should contain("sendmail-like interface")
      status.success?.should be_true
    end

    it "lists catchmail-specific options" do
      output = `#{MAILCATCHER_BIN} catchmail --help 2>&1`

      output.should contain("--smtp-ip")
      output.should contain("--smtp-port")
      output.should contain("-f FROM")
    end
  end

  describe "delivering mail" do
    it "delivers a simple message via stdin" do
      message = <<-EMAIL
      From: sender@example.com
      To: recipient@example.com
      Subject: Test via catchmail

      Hello from catchmail!
      EMAIL

      # Use Process.run to pipe message to stdin
      process = Process.new(
        MAILCATCHER_BIN,
        ["catchmail", "--smtp-port", SMTP_PORT.to_s, "-f", "sender@example.com", "recipient@example.com"],
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      )
      process.input.print(message)
      process.input.close
      status = process.wait

      status.success?.should be_true

      # Verify message was delivered
      messages = api.messages
      messages.size.should eq(1)
      messages[0]["subject"].as_s.should eq("Test via catchmail")

      # Verify body content
      id = messages[0]["id"].as_i64
      plain = api.message_plain(id)
      plain.should contain("Hello from catchmail!")
    end

    it "uses -f flag for sender address" do
      message = <<-EMAIL
      To: recipient@example.com
      Subject: Custom sender test

      Testing custom sender.
      EMAIL

      process = Process.new(
        MAILCATCHER_BIN,
        ["catchmail", "--smtp-port", SMTP_PORT.to_s, "-f", "custom@sender.com", "recipient@example.com"],
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      )
      process.input.print(message)
      process.input.close
      process.wait

      messages = api.messages
      messages.size.should eq(1)
      messages[0]["sender"].as_s.should eq("custom@sender.com")
    end

    it "accepts recipient as command line argument" do
      message = <<-EMAIL
      From: sender@example.com
      Subject: CLI recipient test

      Testing CLI recipient.
      EMAIL

      process = Process.new(
        MAILCATCHER_BIN,
        ["catchmail", "--smtp-port", SMTP_PORT.to_s, "-f", "sender@example.com", "cli-recipient@example.com"],
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      )
      process.input.print(message)
      process.input.close
      process.wait

      messages = api.messages
      messages.size.should eq(1)
      messages[0]["recipients"].as_a.map(&.as_s).should contain("cli-recipient@example.com")
    end

    it "delivers multipart messages" do
      message = read_example("multipartmail")

      process = Process.new(
        MAILCATCHER_BIN,
        ["catchmail", "--smtp-port", SMTP_PORT.to_s, "-f", "sender@example.com", "recipient@example.com"],
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      )
      process.input.print(message)
      process.input.close
      process.wait

      messages = api.messages
      messages.size.should eq(1)
      messages[0]["subject"].as_s.should eq("Test Multipart Mail")

      id = messages[0]["id"].as_i64
      html = api.message_html(id)
      html.should contain("<em>")
    end

    it "handles messages with dots correctly" do
      message = read_example("dotmail")

      process = Process.new(
        MAILCATCHER_BIN,
        ["catchmail", "--smtp-port", SMTP_PORT.to_s, "-f", "sender@example.com", "recipient@example.com"],
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      )
      process.input.print(message)
      process.input.close
      process.wait

      messages = api.messages
      messages.size.should eq(1)

      id = messages[0]["id"].as_i64
      plain = api.message_plain(id)
      plain.should contain(".")
      plain.should contain("...")
    end
  end

  describe "sendmail compatibility options" do
    it "ignores -oi option" do
      message = <<-EMAIL
      From: sender@example.com
      To: recipient@example.com
      Subject: Ignored option test

      Testing ignored options.
      EMAIL

      process = Process.new(
        MAILCATCHER_BIN,
        ["catchmail", "--smtp-port", SMTP_PORT.to_s, "-oi", "-f", "sender@example.com", "recipient@example.com"],
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      )
      process.input.print(message)
      process.input.close
      status = process.wait

      status.success?.should be_true
      api.messages.size.should eq(1)
    end

    it "ignores -t option" do
      message = <<-EMAIL
      From: sender@example.com
      To: recipient@example.com
      Subject: Ignored -t test

      Testing -t option.
      EMAIL

      process = Process.new(
        MAILCATCHER_BIN,
        ["catchmail", "--smtp-port", SMTP_PORT.to_s, "-t", "-f", "sender@example.com", "recipient@example.com"],
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      )
      process.input.print(message)
      process.input.close
      status = process.wait

      status.success?.should be_true
      api.messages.size.should eq(1)
    end
  end

  describe "custom smtp settings" do
    it "respects --smtp-ip and --smtp-port" do
      message = <<-EMAIL
      From: sender@example.com
      To: recipient@example.com
      Subject: Custom port test

      Testing custom port.
      EMAIL

      process = Process.new(
        MAILCATCHER_BIN,
        ["catchmail", "--smtp-ip", LOCALHOST, "--smtp-port", SMTP_PORT.to_s, "-f", "sender@example.com", "recipient@example.com"],
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      )
      process.input.print(message)
      process.input.close
      status = process.wait

      status.success?.should be_true
      api.messages.size.should eq(1)
    end

    it "respects --ip as alias for --smtp-ip" do
      message = <<-EMAIL
      From: sender@example.com
      To: recipient@example.com
      Subject: IP alias test

      Testing --ip alias.
      EMAIL

      process = Process.new(
        MAILCATCHER_BIN,
        ["catchmail", "--ip", LOCALHOST, "--smtp-port", SMTP_PORT.to_s, "-f", "sender@example.com", "recipient@example.com"],
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      )
      process.input.print(message)
      process.input.close
      status = process.wait

      status.success?.should be_true
      api.messages.size.should eq(1)
    end
  end

  describe "multiple recipients" do
    it "delivers to multiple command line recipients" do
      message = <<-EMAIL
      From: sender@example.com
      Subject: Multiple recipients test

      Testing multiple recipients.
      EMAIL

      process = Process.new(
        MAILCATCHER_BIN,
        ["catchmail", "--smtp-port", SMTP_PORT.to_s, "-f", "sender@example.com", "one@example.com", "two@example.com"],
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      )
      process.input.print(message)
      process.input.close
      status = process.wait

      status.success?.should be_true
      messages = api.messages
      messages.size.should eq(1)

      recipients = messages[0]["recipients"].as_a.map(&.as_s)
      recipients.should contain("one@example.com")
      recipients.should contain("two@example.com")
    end
  end
end

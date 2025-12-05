require "./spec_helper"

describe "MailCatcher Delivery" do
  mailcatcher = MailCatcherProcess.new
  smtp = SmtpClient.new
  api = ApiClient.new

  before_each do
    mailcatcher.start
  end

  after_each do
    mailcatcher.stop
  end

  describe "plain text message" do
    it "catches and stores a plain text message" do
      deliver_example("plainmail", smtp)

      messages = api.messages
      messages.size.should eq(1)

      msg = messages[0]
      msg["subject"].as_s.should eq("Plain mail")
    end

    it "returns the plain text body" do
      deliver_example("plainmail", smtp)

      messages = api.messages
      messages.size.should eq(1)

      id = messages[0]["id"].as_i64
      plain = api.message_plain(id)
      plain.should contain("Here's some text")
    end

    it "returns the source" do
      deliver_example("plainmail", smtp)

      messages = api.messages
      id = messages[0]["id"].as_i64

      source = api.message_source(id)
      source.should contain("Subject: Plain mail")
      source.should contain("Here's some text")
    end

    it "shows plain format but not html format" do
      deliver_example("plainmail", smtp)

      messages = api.messages
      id = messages[0]["id"].as_i64

      msg = api.message(id)
      formats = msg["formats"].as_a.map(&.as_s)
      formats.should contain("source")
      formats.should contain("plain")
      formats.should_not contain("html")
    end
  end

  describe "HTML message" do
    it "catches and stores an HTML message" do
      deliver_example("htmlmail", smtp)

      messages = api.messages
      messages.size.should eq(1)

      msg = messages[0]
      msg["subject"].as_s.should eq("Test HTML Mail")
    end

    it "returns the HTML body" do
      deliver_example("htmlmail", smtp)

      messages = api.messages
      id = messages[0]["id"].as_i64

      html = api.message_html(id)
      html.should contain("slimey scoundrel")
      html.should contain("<em>")
    end

    it "shows html format but not plain format" do
      deliver_example("htmlmail", smtp)

      messages = api.messages
      id = messages[0]["id"].as_i64

      msg = api.message(id)
      formats = msg["formats"].as_a.map(&.as_s)
      formats.should contain("source")
      formats.should contain("html")
      formats.should_not contain("plain")
    end
  end

  describe "multipart message" do
    it "catches and stores a multipart message" do
      deliver_example("multipartmail", smtp)

      messages = api.messages
      messages.size.should eq(1)

      msg = messages[0]
      msg["subject"].as_s.should eq("Test Multipart Mail")
    end

    it "returns both plain and HTML parts" do
      deliver_example("multipartmail", smtp)

      messages = api.messages
      id = messages[0]["id"].as_i64

      plain = api.message_plain(id)
      plain.should contain("Plain text mail")

      html = api.message_html(id)
      html.should contain("HTML")
      html.should contain("<em>")
    end

    it "shows both html and plain formats" do
      deliver_example("multipartmail", smtp)

      messages = api.messages
      id = messages[0]["id"].as_i64

      msg = api.message(id)
      formats = msg["formats"].as_a.map(&.as_s)
      formats.should contain("source")
      formats.should contain("html")
      formats.should contain("plain")
    end
  end

  describe "multipart UTF-8 message" do
    it "handles UTF-8 content correctly" do
      deliver_example("multipartmail-with-utf8", smtp)

      messages = api.messages
      messages.size.should eq(1)

      id = messages[0]["id"].as_i64

      html = api.message_html(id)
      html.should contain("©")
    end
  end

  describe "message with attachments" do
    it "catches and stores a message with attachments" do
      deliver_example("attachmail", smtp)

      messages = api.messages
      messages.size.should eq(1)

      msg = messages[0]
      msg["subject"].as_s.should eq("Test Attachment Mail")
    end

    it "lists attachments in the message JSON" do
      deliver_example("attachmail", smtp)

      messages = api.messages
      id = messages[0]["id"].as_i64

      msg = api.message(id)
      attachments = msg["attachments"].as_a
      attachments.size.should eq(1)
      attachments[0]["filename"].as_s.should eq("attachment")
    end

    it "returns the plain text body" do
      deliver_example("attachmail", smtp)

      messages = api.messages
      id = messages[0]["id"].as_i64

      plain = api.message_plain(id)
      plain.should contain("This is plain text")
    end

    it "allows downloading attachments by CID" do
      deliver_example("attachmail", smtp)

      messages = api.messages
      id = messages[0]["id"].as_i64

      msg = api.message(id)
      attachments = msg["attachments"].as_a
      cid = attachments[0]["cid"].as_s

      response = api.get("/messages/#{id}/parts/#{cid}")
      response.status_code.should eq(200)
      response.body.should eq("Hello, I am an attachment!\r\n")
    end
  end

  describe "message with dots" do
    it "handles dot-stuffing correctly" do
      deliver_example("dotmail", smtp)

      messages = api.messages
      messages.size.should eq(1)

      id = messages[0]["id"].as_i64
      plain = api.message_plain(id)
      plain.should contain("With some dot lines:")
      plain.should contain(".")
      plain.should contain("...")
      plain.should contain("Done.")
    end
  end

  describe "quoted-printable message" do
    it "decodes quoted-printable content" do
      deliver_example("quoted_printable_htmlmail", smtp)

      messages = api.messages
      messages.size.should eq(1)

      id = messages[0]["id"].as_i64
      html = api.message_html(id)

      # Check that quoted-printable is decoded
      # =3D should become =
      html.should contain("class=\"slim\"")
      # Soft line breaks should be removed
      html.should contain("demonstrate a limitation")
    end
  end

  describe "multiple messages" do
    it "stores multiple messages" do
      deliver_example("plainmail", smtp)
      deliver_example("htmlmail", smtp)
      deliver_example("multipartmail", smtp)

      messages = api.messages
      messages.size.should eq(3)
    end
  end
end

require "./spec_helper"

describe "MailCatcher Clear" do
  mailcatcher = MailCatcherProcess.new
  smtp = SmtpClient.new
  api = ApiClient.new

  before_each do
    mailcatcher.start
  end

  after_each do
    mailcatcher.stop
  end

  describe "DELETE /messages" do
    it "clears all messages" do
      # Deliver three emails
      deliver_example("plainmail", smtp)
      deliver_example("plainmail", smtp)
      deliver_example("plainmail", smtp)

      # Should have three messages
      messages = api.messages
      messages.size.should eq(3)

      # Clear all messages
      response = api.delete_all_messages
      response.status_code.should eq(204)

      # Should have no messages
      messages = api.messages
      messages.size.should eq(0)
    end
  end

  describe "DELETE /messages/:id" do
    it "deletes a single message" do
      # Deliver three emails
      deliver_example("plainmail", smtp)
      deliver_example("htmlmail", smtp)
      deliver_example("multipartmail", smtp)

      # Should have three messages
      messages = api.messages
      messages.size.should eq(3)

      # Get the ID of the first message
      id = messages[0]["id"].as_i64

      # Delete the first message
      response = api.delete_message(id)
      response.status_code.should eq(204)

      # Should have two messages
      messages = api.messages
      messages.size.should eq(2)
    end

    it "returns 404 for non-existent message" do
      response = api.delete_message(99999)
      response.status_code.should eq(404)
    end
  end
end

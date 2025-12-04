require "./spec_helper"

describe "MailCatcher Command" do
  describe "--version" do
    it "shows a version then exits" do
      output = `#{MAILCATCHER_BIN} --version 2>&1`
      status = $?

      output.should contain("MailCatcher v")
      status.success?.should be_true
    end
  end

  describe "--help" do
    it "shows help then exits" do
      output = `#{MAILCATCHER_BIN} --help 2>&1`
      status = $?

      output.should contain("Usage:")
      output.should contain("--help")
      output.should contain("Display this help")
      status.success?.should be_true
    end

    it "lists all available options" do
      output = `#{MAILCATCHER_BIN} --help 2>&1`

      output.should contain("--smtp-ip")
      output.should contain("--smtp-port")
      output.should contain("--http-ip")
      output.should contain("--http-port")
      output.should contain("--http-path")
      output.should contain("--no-quit")
      output.should contain("--foreground")
      output.should contain("--verbose")
    end
  end

  describe "invalid options" do
    it "shows an error for unknown options" do
      output = `#{MAILCATCHER_BIN} --unknown-option 2>&1`
      status = $?

      output.should contain("is not a valid option")
      status.success?.should be_false
    end
  end
end

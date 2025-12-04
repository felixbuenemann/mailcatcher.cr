# Assets are embedded at compile time using Crystal macros

module MailCatcher
  module Assets
    # JavaScript - text asset
    JAVASCRIPT = {{ read_file("assets/mailcatcher.js") }}

    # CSS - text asset
    STYLESHEET = {{ read_file("assets/mailcatcher.css") }}

    # Favicon - binary asset as Bytes
    FAVICON = {{ read_file("assets/favicon.ico") }}.to_slice

    # Logo images - binary assets as Bytes
    LOGO = {{ read_file("assets/images/logo.png") }}.to_slice
    LOGO_2X = {{ read_file("assets/images/logo_2x.png") }}.to_slice
  end
end

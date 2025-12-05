# MailCatcher (Crystal)

A Crystal port of [MailCatcher](https://github.com/sj26/mailcatcher) v0.10.0 — catches mail and serves it through a crystal.

MailCatcher runs a super simple SMTP server which catches any message sent to it to display in a web interface. Run mailcatcher, set your favourite app to deliver to smtp://127.0.0.1:1025 instead of your default SMTP server, then check out http://127.0.0.1:1080 to see the mail that's arrived so far.

![MailCatcher screenshot](https://cloud.githubusercontent.com/assets/14028/14093249/4100f904-f598-11e5-936b-e6a396f18e39.png)

## Why Crystal?

This is a standalone binary port of the Ruby MailCatcher gem. Benefits:

* **Single binary** — no Ruby, gems, or dependencies to install
* **Fast startup** — native compiled binary starts instantly
* **Low memory** — typically uses less memory than the Ruby version
* **Easy distribution** — just copy the binary
* **No conflicts** - does not conflict with other gems in your Ruby project

## Features

* Catches all mail and stores it for display.
* Shows HTML, Plain Text and Source version of messages, as applicable.
* Rewrites HTML enabling display of embedded, inline images/etc and opens links in a new window.
* Lists attachments and allows separate downloading of parts.
* Download original email to view in your native mail client(s).
* Command line options to override the default SMTP/HTTP IP and port settings.
* Mail appears instantly via WebSockets.
* Runs as a daemon in the background, optionally in foreground.
* Keyboard navigation between messages.
* All assets embedded in binary at compile time.

## Building

### Requirements

* [Crystal](https://crystal-lang.org/install/) >= 1.18.0

### Build

```bash
cd crystal
shards install
crystal build src/mailcatcher.cr -o bin/mailcatcher --release
```

The `--release` flag enables optimizations for a smaller, faster binary.

## Usage

```bash
./mailcatcher
```

Then:
1. Go to http://127.0.0.1:1080/
2. Send mail through smtp://127.0.0.1:1025

## Docker Usage

```bash
docker run --rm -it -p 1080:1080 -p 1025:1025 felixbuenemann/mailcatcher.cr
```

### Command Line Options

```
Usage: mailcatcher [options]

MailCatcher v0.10.0

        --ip IP                      Set the ip address of both servers
        --smtp-ip IP                 Set the ip address of the smtp server
        --smtp-port PORT             Set the port of the smtp server
        --http-ip IP                 Set the ip address of the http server
        --http-port PORT             Set the port of the http server
        --messages-limit COUNT       Only keep up to COUNT most recent messages
        --http-path PATH             Add a prefix to all HTTP paths
        --no-quit                    Don't allow quitting the process
    -f, --foreground                 Run in the foreground
    -b, --browse                     Open web browser
    -v, --verbose                    Be more verbose
    -h, --help                       Display this help information
        --version                    Display the current version
```

## Configuration Examples

### Rails

```ruby
# config/environments/development.rb
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = { address: '127.0.0.1', port: 1025 }
config.action_mailer.raise_delivery_errors = false
```

### Django

```python
# settings.py
if DEBUG:
    EMAIL_HOST = '127.0.0.1'
    EMAIL_HOST_USER = ''
    EMAIL_HOST_PASSWORD = ''
    EMAIL_PORT = 1025
    EMAIL_USE_TLS = False
```

### PHP

```ini
; php.ini
sendmail_path = /usr/bin/env catchmail -f some@from.address
```

Note: The `catchmail` command is not included in this Crystal port. Use a simple script or configure your app to send directly to the SMTP server.

### Node.js (Nodemailer)

```javascript
const transporter = nodemailer.createTransport({
  host: '127.0.0.1',
  port: 1025,
  secure: false,
});
```

## API

A RESTful URL schema means you can download a list of messages in JSON from `/messages`, each message's metadata with `/messages/:id.json`, and then the pertinent parts with `/messages/:id.html` and `/messages/:id.plain` for the default HTML and plain text version, `/messages/:id/parts/:cid` for individual attachments by CID, or the whole message with `/messages/:id.source`.

## Differences from Ruby Version

* No `catchmail` sendmail replacement command (configure apps to use SMTP directly)
* No daemon mode on Windows (uses Unix `daemon()` syscall)
* In-memory message storage uses a hash instead of a SQLite database
* Does not depend on any JavaScript libraries like jQuery
* Uses plain CSS instead of SCSS for styles

## Credits

This is a Crystal port of [MailCatcher](https://github.com/sj26/mailcatcher) by Samuel Cochran (sj26@sj26.com).

Original MailCatcher is released under the MIT License.

## License

Copyright © 2010-2019 Samuel Cochran (sj26@sj26.com) and 2025 Felix Buenemann. Released under the MIT License, see [LICENSE](../LICENSE) for details.

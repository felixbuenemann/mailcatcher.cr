// MailCatcher JavaScript - No dependencies, native DOM APIs only

class MailCatcher {
  constructor() {
    this.quitting = false;
    this.refreshInterval = null;
    this.websocket = null;
    this.faviconCanvas = null;
    this.faviconImage = null;

    this.setupFavicon();
    this.setupEventListeners();
    this.setupKeyboardShortcuts();
    this.resizeToSaved();
    this.refresh();
    this.subscribe();
  }

  // Favicon badge
  setupFavicon() {
    const iconLink = document.querySelector('link[rel="icon"]');
    const iconUrl = iconLink ? iconLink.getAttribute('href') : 'favicon.ico';

    this.faviconCanvas = document.createElement('canvas');
    this.faviconCanvas.width = 16;
    this.faviconCanvas.height = 16;
    this.faviconCtx = this.faviconCanvas.getContext('2d');
    this.faviconImage = new Image();
    this.faviconImage.src = iconUrl;
  }

  updateFavicon(count) {
    const ctx = this.faviconCtx;
    const img = this.faviconImage;

    const draw = () => {
      ctx.clearRect(0, 0, 16, 16);
      ctx.drawImage(img, 0, 0, 16, 16);
      if (count > 0) {
        ctx.fillStyle = '#e74c3c';
        ctx.beginPath();
        ctx.arc(12, 4, 4, 0, 2 * Math.PI);
        ctx.fill();
        ctx.fillStyle = '#fff';
        ctx.font = 'bold 8px Arial';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(count > 9 ? '+' : count.toString(), 12, 4);
      }
      const link = document.querySelector('link[rel="icon"]');
      if (link) {
        link.href = this.faviconCanvas.toDataURL('image/png');
      }
    };

    if (img.complete) {
      draw();
    } else {
      img.onload = draw;
    }
  }

  // Keyboard shortcuts
  setupKeyboardShortcuts() {
    document.addEventListener('keydown', (e) => {
      // Ignore if typing in input
      if (['INPUT', 'SELECT', 'TEXTAREA'].includes(e.target.tagName)) return;

      const key = e.key;
      const ctrl = e.ctrlKey || e.metaKey;

      switch (key) {
        case 'ArrowUp':
          e.preventDefault();
          if (ctrl) {
            const first = document.querySelector('#messages tbody tr[data-message-id]:not([style*="display: none"])');
            if (first) this.loadMessage(first.dataset.messageId);
          } else if (this.selectedMessage()) {
            const selected = document.querySelector('#messages tr.selected');
            const prev = this.getPrevVisibleRow(selected);
            if (prev) this.loadMessage(prev.dataset.messageId);
          } else {
            const first = document.querySelector('#messages tbody tr[data-message-id]');
            if (first) this.loadMessage(first.dataset.messageId);
          }
          break;

        case 'ArrowDown':
          e.preventDefault();
          if (ctrl) {
            const rows = document.querySelectorAll('#messages tbody tr[data-message-id]:not([style*="display: none"])');
            const last = rows[rows.length - 1];
            if (last) this.loadMessage(last.dataset.messageId);
          } else if (this.selectedMessage()) {
            const selected = document.querySelector('#messages tr.selected');
            const next = this.getNextVisibleRow(selected);
            if (next) this.loadMessage(next.dataset.messageId);
          } else {
            const first = document.querySelector('#messages tbody tr[data-message-id]');
            if (first) this.loadMessage(first.dataset.messageId);
          }
          break;

        case 'ArrowLeft':
          e.preventDefault();
          this.openTab(this.previousTab());
          break;

        case 'ArrowRight':
          e.preventDefault();
          this.openTab(this.nextTab());
          break;

        case 'Backspace':
        case 'Delete':
          e.preventDefault();
          const id = this.selectedMessage();
          if (id != null) {
            fetch(new URL(`messages/${id}`, document.baseURI).toString(), { method: 'DELETE' })
              .then(response => {
                if (response.ok) this.removeMessage(id);
                else alert('Error while removing message.');
              })
              .catch(() => alert('Error while removing message.'));
          }
          break;
      }
    });
  }

  setupEventListeners() {
    // Message list click handler (event delegation)
    document.getElementById('messages').addEventListener('click', (e) => {
      const row = e.target.closest('tr[data-message-id]');
      if (row) {
        e.preventDefault();
        this.loadMessage(row.dataset.messageId);
      }
    });

    // Search input
    document.querySelector('input[name=search]').addEventListener('keyup', (e) => {
      const query = e.target.value.trim();
      if (query) {
        this.searchMessages(query);
      } else {
        this.clearSearch();
      }
    });

    // Tab clicks
    document.getElementById('message').addEventListener('click', (e) => {
      const link = e.target.closest('.views .format.tab a');
      if (link) {
        e.preventDefault();
        const tab = link.closest('li');
        this.loadMessageBody(this.selectedMessage(), tab.dataset.messageFormat);
      }
    });

    // iframe load handler
    document.querySelector('#message iframe').addEventListener('load', () => {
      this.decorateMessageBody();
    });

    // Resizer drag
    document.getElementById('resizer').addEventListener('mousedown', (e) => {
      e.preventDefault();
      const onMouseMove = (e) => {
        e.preventDefault();
        this.resizeTo(e.clientY);
      };
      const onMouseUp = () => {
        window.removeEventListener('mousemove', onMouseMove);
        window.removeEventListener('mouseup', onMouseUp);
      };
      window.addEventListener('mousemove', onMouseMove);
      window.addEventListener('mouseup', onMouseUp);
    });

    // Clear button
    document.querySelector('nav.app .clear a').addEventListener('click', (e) => {
      e.preventDefault();
      if (confirm('You will lose all your received messages.\n\nAre you sure you want to clear all messages?')) {
        fetch(new URL('messages', document.baseURI).toString(), { method: 'DELETE' })
          .then(response => {
            if (response.ok) this.clearMessages();
            else alert('Error while clearing all messages.');
          })
          .catch(() => alert('Error while clearing all messages.'));
      }
    });

    // Quit button
    const quitBtn = document.querySelector('nav.app .quit a');
    if (quitBtn) {
      quitBtn.addEventListener('click', (e) => {
        e.preventDefault();
        if (confirm('You will lose all your received messages.\n\nAre you sure you want to quit?')) {
          this.quitting = true;
          fetch(document.baseURI, { method: 'DELETE' })
            .then(response => {
              if (response.ok) this.hasQuit();
              else { this.quitting = false; alert('Error while quitting.'); }
            })
            .catch(() => { this.quitting = false; alert('Error while quitting.'); });
        }
      });
    }
  }

  // Helper to get previous visible sibling row
  getPrevVisibleRow(row) {
    let prev = row.previousElementSibling;
    while (prev && prev.style.display === 'none') {
      prev = prev.previousElementSibling;
    }
    return prev;
  }

  // Helper to get next visible sibling row
  getNextVisibleRow(row) {
    let next = row.nextElementSibling;
    while (next && next.style.display === 'none') {
      next = next.nextElementSibling;
    }
    return next;
  }

  // Date parsing
  parseDateRegexp = /^(\d{4})[-\/\\](\d{2})[-\/\\](\d{2})(?:\s+|T)(\d{2})[:-](\d{2})[:-](\d{2})(?:([ +-]\d{2}:\d{2}|\s*\S+|Z?))?$/;

  parseDate(date) {
    const match = this.parseDateRegexp.exec(date);
    if (match) {
      return new Date(match[1], match[2] - 1, match[3], match[4], match[5], match[6], 0);
    }
    return null;
  }

  formatDate(date) {
    if (typeof date === 'string') {
      date = this.parseDate(date);
    }
    if (!date) return '';

    // Adjust for timezone
    const offset = new Date().getTimezoneOffset() * 60000;
    date = new Date(date.getTime() - offset);

    const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    let hours = date.getHours();
    const ampm = hours >= 12 ? 'PM' : 'AM';
    hours = hours % 12 || 12;

    return `${days[date.getDay()]}, ${date.getDate()} ${months[date.getMonth()]} ${date.getFullYear()} ` +
           `${hours}:${date.getMinutes().toString().padStart(2, '0')}:${date.getSeconds().toString().padStart(2, '0')} ${ampm}`;
  }

  messagesCount() {
    return document.querySelectorAll('#messages tbody tr[data-message-id]').length;
  }

  updateMessagesCount() {
    const count = this.messagesCount();
    this.updateFavicon(count);
    document.title = `MailCatcher (${count})`;
  }

  tabs() {
    return document.querySelectorAll('#message ul .tab');
  }

  getTab(i) {
    return this.tabs()[i];
  }

  selectedTab() {
    return Array.from(this.tabs()).findIndex(tab => tab.classList.contains('selected'));
  }

  openTab(i) {
    const tab = this.getTab(i);
    if (tab) {
      const link = tab.querySelector('a');
      if (link) link.click();
    }
  }

  previousTab(i) {
    if (i === undefined) i = this.selectedTab() - 1;
    const tabs = this.tabs();
    if (i < 0) i = tabs.length - 1;
    const tab = tabs[i];
    return (tab && tab.style.display !== 'none') ? i : this.previousTab(i - 1);
  }

  nextTab(i) {
    if (i === undefined) i = this.selectedTab() + 1;
    const tabs = this.tabs();
    if (i > tabs.length - 1) i = 0;
    const tab = tabs[i];
    return (tab && tab.style.display !== 'none') ? i : this.nextTab(i + 1);
  }

  haveMessage(message) {
    const id = message.id != null ? message.id : message;
    return document.querySelector(`#messages tbody tr[data-message-id="${id}"]`) !== null;
  }

  selectedMessage() {
    const selected = document.querySelector('#messages tr.selected');
    return selected ? selected.dataset.messageId : null;
  }

  searchMessages(query) {
    const tokens = query.toLowerCase().split(/\s+/);
    document.querySelectorAll('#messages tbody tr').forEach(row => {
      const text = row.textContent.toLowerCase();
      row.style.display = tokens.every(token => text.includes(token)) ? '' : 'none';
    });
  }

  clearSearch() {
    document.querySelectorAll('#messages tbody tr').forEach(row => row.style.display = '');
  }

  addMessage(message) {
    const tr = document.createElement('tr');
    tr.dataset.messageId = message.id.toString();

    const fields = [
      { value: message.sender, fallback: 'No sender' },
      { value: (message.recipients || []).join(', '), fallback: 'No recipients' },
      { value: message.subject, fallback: 'No subject' },
      { value: this.formatDate(message.created_at), fallback: '' }
    ];

    fields.forEach(field => {
      const td = document.createElement('td');
      td.textContent = field.value || field.fallback;
      if (!field.value) td.classList.add('blank');
      tr.appendChild(td);
    });

    const tbody = document.querySelector('#messages tbody');
    tbody.insertBefore(tr, tbody.firstChild);
    this.updateMessagesCount();
  }

  removeMessage(id) {
    const row = document.querySelector(`#messages tbody tr[data-message-id="${id}"]`);
    if (!row) return;

    const isSelected = row.classList.contains('selected');
    const next = row.nextElementSibling;
    const prev = row.previousElementSibling;
    const switchTo = (next?.dataset.messageId) || (prev?.dataset.messageId);

    row.remove();

    if (isSelected) {
      switchTo ? this.loadMessage(switchTo) : this.unselectMessage();
    }
    this.updateMessagesCount();
  }

  clearMessages() {
    document.querySelectorAll('#messages tbody tr').forEach(row => row.remove());
    this.unselectMessage();
    this.updateMessagesCount();
  }

  scrollToRow(row) {
    const messages = document.getElementById('messages');
    const rowRect = row.getBoundingClientRect();
    const messagesRect = messages.getBoundingClientRect();
    const relativePosition = rowRect.top - messagesRect.top;

    if (relativePosition < 0) {
      messages.scrollTop += relativePosition - 20;
    } else {
      const overflow = relativePosition + rowRect.height - messagesRect.height;
      if (overflow > 0) messages.scrollTop += overflow + 20;
    }
  }

  unselectMessage() {
    document.querySelectorAll('#messages tbody tr.selected').forEach(row => row.classList.remove('selected'));
    document.querySelectorAll('#message .metadata dd').forEach(dd => dd.textContent = '');
    document.querySelector('#message .metadata .attachments').style.display = 'none';
    document.querySelector('#message iframe').src = 'about:blank';
  }

  loadMessage(id) {
    if (id?.id) id = id.id;
    if (!id) {
      const selected = document.querySelector('#messages tr.selected');
      id = selected?.dataset.messageId;
    }
    if (!id) return;

    document.querySelectorAll(`#messages tbody tr:not([data-message-id='${id}'])`).forEach(row => {
      row.classList.remove('selected');
    });
    const messageRow = document.querySelector(`#messages tbody tr[data-message-id='${id}']`);
    if (messageRow) {
      messageRow.classList.add('selected');
      this.scrollToRow(messageRow);
    }

    fetch(`messages/${id}.json`)
      .then(r => r.json())
      .then(message => {
        document.querySelector('#message .metadata dd.created_at').textContent = this.formatDate(message.created_at);
        document.querySelector('#message .metadata dd.from').textContent = message.sender;
        document.querySelector('#message .metadata dd.to').textContent = (message.recipients || []).join(', ');
        document.querySelector('#message .metadata dd.subject').textContent = message.subject;

        document.querySelectorAll('#message .views .tab.format').forEach(tab => {
          const format = tab.dataset.messageFormat;
          if (message.formats.includes(format)) {
            tab.querySelector('a').href = `messages/${id}.${format}`;
            tab.style.display = '';
          } else {
            tab.style.display = 'none';
          }
        });

        const selectedTab = document.querySelector('#message .views .tab.selected');
        if (selectedTab?.style.display === 'none') {
          selectedTab.classList.remove('selected');
          document.querySelector('#message .views .tab.format:not([style*="display: none"])')?.classList.add('selected');
        }

        const attachmentsDD = document.querySelector('#message .metadata dd.attachments');

        if (message.attachments?.length) {
          attachmentsDD.innerHTML = '';
          const ul = document.createElement('ul');
          message.attachments.forEach(att => {
            const li = document.createElement('li');
            const a = document.createElement('a');
            a.href = `messages/${id}/parts/${att.cid}`;
            a.className = `${att.type.split('/')[0]} ${att.type.replace('/', '-')}`;
            a.textContent = att.filename;
            li.appendChild(a);
            ul.appendChild(li);
          });
          attachmentsDD.appendChild(ul);
          // Show BOTH dt.attachments and dd.attachments
          document.querySelectorAll('#message .metadata .attachments').forEach(el => el.style.display = 'block');
        } else {
          document.querySelectorAll('#message .metadata .attachments').forEach(el => el.style.display = '');
        }

        document.querySelector('#message .views .download a').href = `messages/${id}.eml`;
        this.loadMessageBody();
      });
  }

  loadMessageBody(id, format) {
    id = id || this.selectedMessage();
    format = format || document.querySelector('#message .views .tab.format.selected')?.dataset.messageFormat || 'html';

    document.querySelectorAll(`#message .views .tab[data-message-format="${format}"]`).forEach(t => t.classList.add('selected'));
    document.querySelectorAll(`#message .views .tab:not([data-message-format="${format}"])`).forEach(t => t.classList.remove('selected'));

    if (id) document.querySelector('#message iframe').src = `messages/${id}.${format}`;
  }

  decorateMessageBody() {
    const format = document.querySelector('#message .views .tab.format.selected')?.dataset.messageFormat;
    const iframe = document.querySelector('#message iframe');

    try {
      const doc = iframe.contentDocument || iframe.contentWindow.document;

      if (format === 'html') {
        doc.querySelectorAll('a').forEach(a => a.target = '_blank');
      } else if (format === 'plain') {
        let text = doc.body.textContent || '';
        text = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
        text = text.replace(/((https?|ftp):\/\/[\w\-_]+(\.[\w\-_]+)+([\w\-.,@?^=%&:\/~+#]*[\w\-@?^=%&\/~+#])?)/g,
                            '<a href="$1" target="_blank">$1</a>');
        doc.documentElement.innerHTML = `<body style="font-family: sans-serif; white-space: pre-wrap">${text}</body>`;
      }
    } catch (e) { /* cross-origin */ }
  }

  refresh() {
    fetch('messages')
      .then(r => r.json())
      .then(messages => {
        messages.forEach(msg => { if (!this.haveMessage(msg)) this.addMessage(msg); });
        this.updateMessagesCount();
      });
  }

  subscribe() {
    if (typeof WebSocket !== 'undefined') {
      const url = new URL('messages', document.baseURI);
      url.protocol = location.protocol === 'https:' ? 'wss' : 'ws';
      this.websocket = new WebSocket(url.toString());
      this.websocket.onmessage = (event) => {
        const data = JSON.parse(event.data);
        if (data.type === 'add') this.addMessage(data.message);
        else if (data.type === 'remove') this.removeMessage(data.id);
        else if (data.type === 'clear') this.clearMessages();
        else if (data.type === 'quit' && !this.quitting) { alert('MailCatcher has been quit'); this.hasQuit(); }
      };
    } else {
      this.refreshInterval = setInterval(() => this.refresh(), 1000);
    }
  }

  resizeToSavedKey = 'mailcatcherSeparatorHeight';

  resizeTo(height) {
    const messages = document.getElementById('messages');
    messages.style.height = (height - messages.getBoundingClientRect().top) + 'px';
    localStorage?.setItem(this.resizeToSavedKey, height);
  }

  resizeToSaved() {
    const height = parseInt(localStorage?.getItem(this.resizeToSavedKey));
    if (!isNaN(height)) this.resizeTo(height);
  }

  hasQuit() {
    const link = document.querySelector('body > header h1 a');
    if (link) location.assign(link.href);
  }
}

document.addEventListener('DOMContentLoaded', () => window.MailCatcher = new MailCatcher());

const serverInput = document.getElementById('server');
const tokenInput = document.getElementById('token');
const status = document.getElementById('status');

chrome.storage.sync.get(['seenlyServer', 'seenlyToken'], ({ seenlyServer, seenlyToken }) => {
  if (seenlyServer) serverInput.value = seenlyServer;
  if (seenlyToken) tokenInput.value = seenlyToken;
});

document.getElementById('save').addEventListener('click', () => {
  const seenlyServer = serverInput.value.trim();
  const seenlyToken = tokenInput.value.trim();
  if (!seenlyServer || !seenlyToken) {
    status.textContent = 'both fields are needed';
    return;
  }
  chrome.storage.sync.set({ seenlyServer, seenlyToken }, () => {
    status.textContent = 'saved — start watching something';
    setTimeout(() => (status.textContent = ''), 2500);
  });
});

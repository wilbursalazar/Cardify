const api = typeof browser !== 'undefined' ? browser : chrome;
const status = document.getElementById('status');
const selection = document.getElementById('selection');
const send = document.getElementById('send');
async function prepareClip() {
  try {
    const [tab] = await api.tabs.query({active: true, currentWindow: true});
    if (!tab || !/^https?:\/\//i.test(tab.url || '')) throw new Error('Open a regular web page first. Browser settings and local pages are not supported.');
    const results = await api.scripting.executeScript({target: {tabId: tab.id}, func: () => window.getSelection().toString()});
    const text = results[0]?.result || '';
    const params = [['title', tab.title || ''], ['text', text], ['source', tab.url]]
      .map(([key, value]) => key + '=' + encodeURIComponent(value)).join('&');
    const link = 'cardifyresearch://clip?' + params;
    if (new TextEncoder().encode(link).length > 12000) throw new Error('This selection is too long to send. Select a shorter passage and try again.');
    status.textContent = text ? 'Selected passage from: ' + (tab.title || tab.url) : 'No text selected. The page title and source will be added.';
    selection.textContent = text;
    send.href = link;
    send.hidden = false;
  } catch (error) {
    status.textContent = error.message || 'This page cannot be clipped. Try a regular web page.';
  }
}
prepareClip();

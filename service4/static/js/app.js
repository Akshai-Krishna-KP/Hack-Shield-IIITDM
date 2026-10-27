(() => {
  const $ = (selector) => document.querySelector(selector);
  const show = (el) => el && el.classList.remove('hidden');
  const hide = (el) => el && el.classList.add('hidden');
  const search = (inputSelector, itemSelector, emptySelector) => {
    const input = $(inputSelector); if (!input) return;
    const items = [...document.querySelectorAll(itemSelector)];
    const empty = emptySelector ? $(emptySelector) : null;
    input.addEventListener('input', () => {
      const q = input.value.trim().toLowerCase(); let count = 0;
      items.forEach(item => { const text = (item.innerText + ' ' + (item.dataset.search || '')).toLowerCase(); const match = text.includes(q); item.classList.toggle('hidden', !match); if (match) count++; });
      if (empty) empty.classList.toggle('hidden', count !== 0);
    });
  };
  search('#articleSearch', '.wiki-item', '#emptySearch');
  search('#peopleSearch', '.person-card');
  document.addEventListener('keydown', e => { if (e.key === '/' && !['INPUT','TEXTAREA'].includes(document.activeElement.tagName)) { const input = $('#articleSearch') || $('#peopleSearch'); if (input) { e.preventDefault(); input.focus(); } } });
  const form = $('#previewForm');
  if (form) {
    const input = $('#urlInput'), placeholder = $('#resultPlaceholder'), loading = $('#loadingState'), result = $('#previewResult'), error = $('#errorState');
    const runPreview = async (url) => {
      hide(placeholder); hide(result); hide(error); show(loading);
      try {
        const response = await fetch('/api/preview?url=' + encodeURIComponent(url));
        const data = await response.json(); hide(loading);
        if (!response.ok) { error.textContent = data.error || 'The preview request failed.'; show(error); return; }
        $('#statusBadge').textContent = `${data.status_code} ${data.status_code >= 200 && data.status_code < 300 ? 'OK' : 'Response'}`;
        $('#statusBadge').classList.toggle('bad', data.status_code >= 400);
        $('#responseType').textContent = data.content_type || 'Response'; $('#responseUrl').textContent = data.url;
        $('#responseBody').textContent = data.preview_snippet || '(Empty response body)'; show(result);
      } catch (_) { hide(loading); error.textContent = 'Could not reach the preview service. Check that the service is running and try again.'; show(error); }
    };
    form.addEventListener('submit', e => { e.preventDefault(); if (input.reportValidity()) runPreview(input.value.trim()); });
    document.querySelectorAll('.example-link').forEach(btn => btn.addEventListener('click', () => { input.value = btn.dataset.url; runPreview(input.value); }));
    const copy = $('#copyResult'); if (copy) copy.addEventListener('click', async () => { try { await navigator.clipboard.writeText($('#responseBody').textContent); copy.textContent = 'Copied ✓'; setTimeout(() => copy.textContent = 'Copy response', 1500); } catch (_) { copy.textContent = 'Select and copy the response'; } });
  }
})();
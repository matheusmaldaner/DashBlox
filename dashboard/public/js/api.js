// fetch wrapper for all api calls

const api = { // eslint-disable-line no-unused-vars
  // post json and return json
  async postJSON(url, data) {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: res.statusText }));
      throw new Error(err.error || `request failed: ${res.status}`);
    }
    return res.json();
  },

  // post json and return blob (for audio/binary responses)
  async postBlob(url, data) {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: res.statusText }));
      throw new Error(err.error || `request failed: ${res.status}`);
    }
    return res.blob();
  },

  // get json
  async getJSON(url) {
    const res = await fetch(url);
    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: res.statusText }));
      throw new Error(err.error || `request failed: ${res.status}`);
    }
    return res.json();
  },

  // put json
  async putJSON(url, data) {
    const res = await fetch(url, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: res.statusText }));
      throw new Error(err.error || `request failed: ${res.status}`);
    }
    return res.json();
  },

  // delete json
  async deleteJSON(url) {
    const res = await fetch(url, { method: 'DELETE' });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: res.statusText }));
      throw new Error(err.error || `request failed: ${res.status}`);
    }
    return res.json();
  },
};

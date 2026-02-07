// board tab - kanban task manager with drag-and-drop

(function () {
  let columns = [];
  let cards = [];
  let editingCard = null;
  let filterPriority = '';
  let filterLabel = '';
  const filterAssignee = '';
  let searchQuery = '';

  const LABELS = ['building', 'audio', 'ui', 'bug', 'feature'];

  // svg icons
  const plusIcon =
    '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>';
  const trashIcon =
    '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>';
  const userIcon =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>';

  document.addEventListener('DOMContentLoaded', () => {
    initBoard();
  });

  function initBoard() {
    const searchInput = document.getElementById('boardSearch');
    const priorityFilter = document.getElementById('boardFilterPriority');
    const labelFilter = document.getElementById('boardFilterLabel');
    const addColumnBtn = document.getElementById('boardAddColumnBtn');

    if (!searchInput) return;

    searchInput.addEventListener('input', debounce(() => {
      searchQuery = searchInput.value.trim();
      renderBoard();
    }, 300));

    priorityFilter.addEventListener('change', () => {
      filterPriority = priorityFilter.value;
      renderBoard();
    });

    labelFilter.addEventListener('change', () => {
      filterLabel = labelFilter.value;
      renderBoard();
    });

    addColumnBtn.addEventListener('click', addColumn);

    // close modal on overlay click
    const modal = document.getElementById('cardModal');
    modal.addEventListener('click', (e) => {
      if (e.target === modal) closeCardModal();
    });

    document.getElementById('cardModalCancel').addEventListener('click', closeCardModal);
    document.getElementById('cardModalSave').addEventListener('click', saveCard);
    document.getElementById('cardModalDelete').addEventListener('click', deleteCard);

    loadBoard();
  }

  async function loadBoard() {
    try {
      const [colRes, cardRes] = await Promise.all([
        api.getJSON('/api/board/columns'),
        api.getJSON('/api/board/cards'),
      ]);
      columns = colRes.data;
      cards = cardRes.data;

      // create default columns if none exist
      if (columns.length === 0) {
        await createDefaultColumns();
      }

      renderBoard();
    } catch (err) {
      console.error('failed to load board:', err);
      // render empty board with defaults for offline mode
      columns = [
        { _id: 'temp-1', title: 'To Do', position: 0 },
        { _id: 'temp-2', title: 'In Progress', position: 1 },
        { _id: 'temp-3', title: 'Review', position: 2 },
        { _id: 'temp-4', title: 'Done', position: 3 },
      ];
      cards = [];
      renderBoard();
    }
  }

  async function createDefaultColumns() {
    const defaults = ['To Do', 'In Progress', 'Review', 'Done'];
    for (const title of defaults) {
      try {
        const res = await api.postJSON('/api/board/columns', { title });
        columns.push(res.data);
      } catch {
        // fallback for offline
        columns.push({ _id: 'temp-' + columns.length, title, position: columns.length });
      }
    }
  }

  function renderBoard() {
    const container = document.getElementById('boardContainer');
    container.innerHTML = '';

    const sortedColumns = [...columns].sort((a, b) => a.position - b.position);

    sortedColumns.forEach((col) => {
      const colEl = createColumnElement(col);
      container.appendChild(colEl);
    });

    // add column button
    const addBtn = document.createElement('button');
    addBtn.className = 'board-add-column';
    addBtn.id = 'boardAddColumnBtn';
    addBtn.innerHTML = plusIcon + ' add column';
    addBtn.addEventListener('click', addColumn);
    container.appendChild(addBtn);

    // initialize sortable on each card list
    initDragAndDrop();
  }

  function createColumnElement(col) {
    const colEl = document.createElement('div');
    colEl.className = 'board-column glass-panel';
    colEl.dataset.columnId = col._id;

    const colCards = getFilteredCards(col._id);

    colEl.innerHTML = `
      <div class="board-column-header">
        <h3>
          ${escapeHtml(col.title)}
          <span class="board-column-count">${colCards.length}</span>
        </h3>
        <div class="board-column-actions">
          <button class="col-delete-btn" title="delete column">${trashIcon}</button>
        </div>
      </div>
      <div class="board-quick-add">
        <input type="text" placeholder="add a card..." class="quick-add-input" data-column-id="${col._id}">
      </div>
      <div class="board-card-list" data-column-id="${col._id}"></div>
    `;

    // quick add input handler
    const quickAddInput = colEl.querySelector('.quick-add-input');
    quickAddInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && quickAddInput.value.trim()) {
        quickAddCard(col._id, quickAddInput.value.trim());
        quickAddInput.value = '';
      }
    });

    // delete column handler
    const deleteBtn = colEl.querySelector('.col-delete-btn');
    deleteBtn.addEventListener('click', () => deleteColumn(col._id));

    // render cards
    const cardList = colEl.querySelector('.board-card-list');
    colCards.forEach((card) => {
      cardList.appendChild(createCardElement(card));
    });

    return colEl;
  }

  function createCardElement(card) {
    const cardEl = document.createElement('div');
    cardEl.className = 'board-card';
    cardEl.dataset.cardId = card._id;

    const labelsHtml = (card.labels || [])
      .map((l) => {
        const cls = LABELS.includes(l) ? `label-${l}` : 'label-default';
        return `<span class="board-card-label ${cls}">${escapeHtml(l)}</span>`;
      })
      .join('');

    const assigneeHtml = card.assignee
      ? `<span class="board-card-assignee">${userIcon} ${escapeHtml(card.assignee)}</span>`
      : '';

    const dueHtml = card.due_date
      ? `<span class="board-card-due ${isOverdue(card.due_date) ? 'overdue' : ''}">${formatDate(card.due_date)}</span>`
      : '';

    cardEl.innerHTML = `
      <div class="board-card-priority priority-${card.priority || 'medium'}"></div>
      <div class="board-card-title">${escapeHtml(card.title)}</div>
      ${labelsHtml ? `<div class="board-card-labels">${labelsHtml}</div>` : ''}
      ${assigneeHtml || dueHtml ? `<div class="board-card-footer">${assigneeHtml}${dueHtml}</div>` : ''}
    `;

    cardEl.addEventListener('click', () => openCardModal(card));

    return cardEl;
  }

  function getFilteredCards(columnId) {
    return cards
      .filter((c) => c.column_id === columnId)
      .filter((c) => {
        if (filterPriority && c.priority !== filterPriority) return false;
        if (filterLabel && !(c.labels || []).includes(filterLabel)) return false;
        if (filterAssignee && c.assignee !== filterAssignee) return false;
        if (searchQuery) {
          const q = searchQuery.toLowerCase();
          const matchTitle = (c.title || '').toLowerCase().includes(q);
          const matchDesc = (c.description || '').toLowerCase().includes(q);
          if (!matchTitle && !matchDesc) return false;
        }
        return true;
      })
      .sort((a, b) => (a.position || 0) - (b.position || 0));
  }

  function initDragAndDrop() {
    if (typeof Sortable === 'undefined') return;

    const cardLists = document.querySelectorAll('.board-card-list');
    cardLists.forEach((list) => {
      new Sortable(list, {
        group: 'board-cards',
        animation: 200,
        ghostClass: 'sortable-ghost',
        dragClass: 'sortable-drag',
        onEnd: handleDragEnd,
      });
    });
  }

  async function handleDragEnd(evt) {
    const cardId = evt.item.dataset.cardId;
    const newColumnId = evt.to.dataset.columnId;
    const newPosition = evt.newIndex;

    // update local state
    const card = cards.find((c) => c._id === cardId);
    if (card) {
      card.column_id = newColumnId;
      card.position = newPosition;
    }

    // persist to server
    try {
      await api.putJSON(`/api/board/cards/${cardId}/move`, {
        column_id: newColumnId,
        position: newPosition,
      });
    } catch (err) {
      console.error('failed to move card:', err);
      showToast('failed to save card position');
    }

    // update column counts
    updateColumnCounts();
  }

  function updateColumnCounts() {
    document.querySelectorAll('.board-column').forEach((colEl) => {
      const colId = colEl.dataset.columnId;
      const count = getFilteredCards(colId).length;
      const countEl = colEl.querySelector('.board-column-count');
      if (countEl) countEl.textContent = count;
    });
  }

  async function quickAddCard(columnId, title) {
    try {
      const res = await api.postJSON('/api/board/cards', {
        column_id: columnId,
        title,
      });
      cards.push(res.data);
      renderBoard();
    } catch (err) {
      console.error('failed to add card:', err);
      // add locally for offline mode
      cards.push({
        _id: 'temp-' + Date.now(),
        column_id: columnId,
        title,
        priority: 'medium',
        labels: [],
        position: cards.filter((c) => c.column_id === columnId).length,
      });
      renderBoard();
    }
  }

  async function addColumn() {
    const title = prompt('column name:');
    if (!title) return;

    try {
      const res = await api.postJSON('/api/board/columns', { title });
      columns.push(res.data);
      renderBoard();
    } catch (err) {
      console.error('failed to add column:', err);
      columns.push({ _id: 'temp-' + Date.now(), title, position: columns.length });
      renderBoard();
    }
  }

  async function deleteColumn(columnId) {
    if (!confirm('delete this column and all its cards?')) return;

    try {
      await api.deleteJSON(`/api/board/columns/${columnId}`);
    } catch (err) {
      console.error('failed to delete column:', err);
    }

    columns = columns.filter((c) => c._id !== columnId);
    cards = cards.filter((c) => c.column_id !== columnId);
    renderBoard();
  }

  // card modal
  function openCardModal(card) {
    editingCard = card;
    const modal = document.getElementById('cardModal');

    document.getElementById('cardModalTitle').value = card.title || '';
    document.getElementById('cardModalDesc').value = card.description || '';
    document.getElementById('cardModalPriority').value = card.priority || 'medium';
    document.getElementById('cardModalAssignee').value = card.assignee || '';
    document.getElementById('cardModalDue').value = card.due_date
      ? card.due_date.substring(0, 10)
      : '';

    // set label chips
    const labelContainer = document.getElementById('cardModalLabels');
    labelContainer.innerHTML = '';
    LABELS.forEach((l) => {
      const chip = document.createElement('button');
      chip.className = 'label-chip' + ((card.labels || []).includes(l) ? ' selected' : '');
      chip.textContent = l;
      chip.type = 'button';
      chip.addEventListener('click', () => chip.classList.toggle('selected'));
      labelContainer.appendChild(chip);
    });

    // show delete button only for existing cards
    document.getElementById('cardModalDelete').style.display =
      card._id && !card._id.startsWith('temp-') ? 'inline-flex' : 'none';

    modal.classList.add('active');
  }

  function closeCardModal() {
    document.getElementById('cardModal').classList.remove('active');
    editingCard = null;
  }

  async function saveCard() {
    if (!editingCard) return;

    const title = document.getElementById('cardModalTitle').value.trim();
    if (!title) {
      showToast('title is required');
      return;
    }

    const selectedLabels = [];
    document.querySelectorAll('#cardModalLabels .label-chip.selected').forEach((chip) => {
      selectedLabels.push(chip.textContent);
    });

    const data = {
      title,
      description: document.getElementById('cardModalDesc').value,
      priority: document.getElementById('cardModalPriority').value,
      assignee: document.getElementById('cardModalAssignee').value || null,
      due_date: document.getElementById('cardModalDue').value || null,
      labels: selectedLabels,
    };

    try {
      const res = await api.putJSON(`/api/board/cards/${editingCard._id}`, data);
      // update local state
      const idx = cards.findIndex((c) => c._id === editingCard._id);
      if (idx !== -1) cards[idx] = res.data;
    } catch (err) {
      console.error('failed to save card:', err);
      // update locally for offline
      const idx = cards.findIndex((c) => c._id === editingCard._id);
      if (idx !== -1) Object.assign(cards[idx], data);
    }

    closeCardModal();
    renderBoard();
  }

  async function deleteCard() {
    if (!editingCard) return;

    try {
      await api.deleteJSON(`/api/board/cards/${editingCard._id}`);
    } catch (err) {
      console.error('failed to delete card:', err);
    }

    cards = cards.filter((c) => c._id !== editingCard._id);
    closeCardModal();
    renderBoard();
  }

  // helpers
  function isOverdue(dateStr) {
    if (!dateStr) return false;
    return new Date(dateStr) < new Date();
  }

  function formatDate(dateStr) {
    if (!dateStr) return '';
    const d = new Date(dateStr);
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  }

  function showToast(message) {
    const container = document.getElementById('toastContainer');
    if (!container) return;
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;
    container.appendChild(toast);
    setTimeout(() => toast.remove(), 3000);
  }

  function escapeHtml(str) {
    if (!str) return '';
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }

  function debounce(fn, ms) {
    let timer;
    return function (...args) {
      clearTimeout(timer);
      timer = setTimeout(() => fn.apply(this, args), ms);
    };
  }
})();

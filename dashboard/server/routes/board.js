// board routes - kanban columns and cards CRUD

const express = require('express');
const router = express.Router();
const BoardColumn = require('../models/BoardColumn');
const BoardCard = require('../models/BoardCard');

// GET /api/board/columns - list all columns
router.get('/columns', async (_req, res, next) => {
  try {
    const columns = await BoardColumn.find().sort({ position: 1 }).lean();
    res.json({ success: true, data: columns });
  } catch (err) {
    next(err);
  }
});

// POST /api/board/columns - create column
router.post('/columns', async (req, res, next) => {
  try {
    const { title } = req.body;
    if (!title) {
      throw Object.assign(new Error('title is required'), { status: 400 });
    }

    // set position to the end
    const count = await BoardColumn.countDocuments();
    const column = await BoardColumn.create({ title, position: count });

    res.status(201).json({ success: true, data: column });
  } catch (err) {
    next(err);
  }
});

// PUT /api/board/columns/:id - update column
router.put('/columns/:id', async (req, res, next) => {
  try {
    const { title, position } = req.body;
    const update = {};
    if (title !== undefined) update.title = title;
    if (position !== undefined) update.position = position;

    const column = await BoardColumn.findByIdAndUpdate(req.params.id, update, { new: true });
    if (!column) {
      throw Object.assign(new Error('column not found'), { status: 404 });
    }

    res.json({ success: true, data: column });
  } catch (err) {
    next(err);
  }
});

// DELETE /api/board/columns/:id - delete column and its cards
router.delete('/columns/:id', async (req, res, next) => {
  try {
    const column = await BoardColumn.findByIdAndDelete(req.params.id);
    if (!column) {
      throw Object.assign(new Error('column not found'), { status: 404 });
    }

    // delete all cards in this column
    await BoardCard.deleteMany({ column_id: req.params.id });

    res.json({ success: true, data: { deleted: true } });
  } catch (err) {
    next(err);
  }
});

// GET /api/board/cards - list cards with optional filters
router.get('/cards', async (req, res, next) => {
  try {
    const filter = {};
    if (req.query.column_id) filter.column_id = req.query.column_id;
    if (req.query.priority) filter.priority = req.query.priority;
    if (req.query.assignee) filter.assignee = req.query.assignee;
    if (req.query.label) filter.labels = req.query.label;
    if (req.query.search) {
      filter.$or = [
        { title: { $regex: req.query.search, $options: 'i' } },
        { description: { $regex: req.query.search, $options: 'i' } },
      ];
    }

    const cards = await BoardCard.find(filter).sort({ position: 1 }).lean();
    res.json({ success: true, data: cards });
  } catch (err) {
    next(err);
  }
});

// POST /api/board/cards - create card
router.post('/cards', async (req, res, next) => {
  try {
    const { column_id, title, description, priority, labels, assignee, due_date } = req.body;

    if (!column_id || !title) {
      throw Object.assign(new Error('column_id and title are required'), { status: 400 });
    }

    // set position to end of column
    const count = await BoardCard.countDocuments({ column_id });
    const card = await BoardCard.create({
      column_id,
      title,
      description: description || '',
      priority: priority || 'medium',
      labels: labels || [],
      assignee: assignee || null,
      due_date: due_date || null,
      position: count,
    });

    res.status(201).json({ success: true, data: card });
  } catch (err) {
    next(err);
  }
});

// PUT /api/board/cards/:id - update card
router.put('/cards/:id', async (req, res, next) => {
  try {
    const { title, description, priority, labels, assignee, due_date, column_id, position } =
      req.body;
    const update = {};
    if (title !== undefined) update.title = title;
    if (description !== undefined) update.description = description;
    if (priority !== undefined) update.priority = priority;
    if (labels !== undefined) update.labels = labels;
    if (assignee !== undefined) update.assignee = assignee;
    if (due_date !== undefined) update.due_date = due_date;
    if (column_id !== undefined) update.column_id = column_id;
    if (position !== undefined) update.position = position;
    update.updated_at = new Date();

    const card = await BoardCard.findByIdAndUpdate(req.params.id, update, { new: true });
    if (!card) {
      throw Object.assign(new Error('card not found'), { status: 404 });
    }

    res.json({ success: true, data: card });
  } catch (err) {
    next(err);
  }
});

// DELETE /api/board/cards/:id - delete card
router.delete('/cards/:id', async (req, res, next) => {
  try {
    const card = await BoardCard.findByIdAndDelete(req.params.id);
    if (!card) {
      throw Object.assign(new Error('card not found'), { status: 404 });
    }

    res.json({ success: true, data: { deleted: true } });
  } catch (err) {
    next(err);
  }
});

// PUT /api/board/cards/:id/move - move card between columns
router.put('/cards/:id/move', async (req, res, next) => {
  try {
    const { column_id, position } = req.body;
    if (!column_id || position === undefined) {
      throw Object.assign(new Error('column_id and position are required'), { status: 400 });
    }

    const card = await BoardCard.findByIdAndUpdate(
      req.params.id,
      { column_id, position, updated_at: new Date() },
      { new: true }
    );
    if (!card) {
      throw Object.assign(new Error('card not found'), { status: 404 });
    }

    res.json({ success: true, data: card });
  } catch (err) {
    next(err);
  }
});

module.exports = router;

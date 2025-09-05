const pool = require('../config/db');


const createToll = async (req, res) => {
  try {
    const { name } = req.body;
    const [rows] = await pool.query('SELECT * FROM tolls WHERE name = ?', [name]);
    if (rows.length > 0) {
      return res.status(400).json({
        ok: false,
        message: 'Toll already exists'
      });
    }
    await pool.query('INSERT INTO tolls (name) VALUES (?)', [name]);
    res.status(201).json({
      ok: true,
      message: 'Toll created successfully',
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: 'INTERNAL_SERVER_ERROR'
    });
  }
};

module.exports = { createToll };
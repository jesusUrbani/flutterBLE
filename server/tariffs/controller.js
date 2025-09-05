const pool = require('../config/db');


const getTariff = async (req, res) => {
  try {
    const { toll_id, vehicle_type } = req.query;
    const [rows] = await pool.query('SELECT * FROM tariffs WHERE toll_id = ? AND vehicle_type = ?', [toll_id, vehicle_type]);

    if (rows.length === 0) {
      return res.status(404).json({
        ok: false,
        message: 'Tariff not found for the specified toll and vehicle type'
      });
    }

    res.status(200).json({
      ok: true,
      message: 'Tariff obtained successfully',
      data: rows[0]
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: 'INTERNAL_SERVER_ERROR'
    });
  }
};


const createTariff = async (req, res) => {
  try {
    const { toll_id, vehicle_type, tariff } = req.body;
    
    const [rows] = await pool.query('SELECT * FROM tariffs WHERE toll_id = ? AND vehicle_type = ?', [toll_id, vehicle_type]);
    if (rows.length > 0) {
      return res.status(400).json({
        ok: false,
        message: 'Tariff already exists for the specified toll and vehicle type'
      });
    }
    
    await pool.query('INSERT INTO tariffs (toll_id, vehicle_type, tariff) VALUES (?, ?, ?)', [toll_id, vehicle_type, tariff]);
    res.status(201).json({
      ok: true,
      message: 'Tariff created successfully',
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: 'INTERNAL_SERVER_ERROR'
    });
  }
};

const updateTariff = async (req, res) => {
  try {
    const { id, tariff } = req.body;
    await pool.query('UPDATE tariffs SET tariff = ? WHERE id = ?', [tariff, id]);
    res.status(200).json({
      ok: true,
      message: 'Tariff updated successfully',
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      message: 'INTERNAL_SERVER_ERROR'
    });
  }
};

module.exports = { getTariff, createTariff, updateTariff };
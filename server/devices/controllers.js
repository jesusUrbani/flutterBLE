const pool = require('../config/db');


const registerDevice = async (req, res) => {
  try {
    const { id_dispositivo, id_zona, nombre_dispositivo, tipo_dispositivo } = req.body;

    const [rows] = await pool.query(
      'INSERT INTO dispositivos (id_dispositivo, id_zona, nombre_dispositivo, tipo_dispositivo) VALUES (?, ?, ?, ?)',
      [id_dispositivo, id_zona, nombre_dispositivo, tipo_dispositivo]
    );

    const data = {
      message: 'Dispositivo registrado exitosamente',
      data: rows[0]
    }

    res.status(201).json(data);
  } catch (error) {
    console.log(error);
    res.status(500).json({ error: 'INTERNAL_SERVER_ERROR' });
  }
};

const getAllDevices = async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT * FROM dispositivos');
    const data = {
      message: 'Dispositivos obtenidos exitosamente',
      data: rows
    }
    res.status(200).json(data);
  } catch (error) {
    console.log(error);
    res.status(500).json({ error: 'INTERNAL_SERVER_ERROR' });
  }
};

module.exports = { registerDevice, getAllDevices };
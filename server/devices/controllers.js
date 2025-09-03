const { pool } = require('../config/db');

const ESP32_IP = 'http://192.168.0.252';
const ESP32_ENDPOINT = '/activate-led';

const getAllDevices = async (req, res) => {
  try {
    const [rows] = await pool.query(`
      SELECT 
        rib.id_usuario,
        rib.nombre_entrada, 
        rib.total_pagado,
        rib.estado as estado_ingreso,
        rp.placas,
        rv.archivo as video_asociado
      FROM registros_ingresoBLE rib
      LEFT JOIN registros_placas rp ON rib.id = rp.id_ingreso 
      LEFT JOIN registros_videoclips rv ON rib.id = rv.id_ingreso
    `);

    const data = {
      message: 'Dispositivos obtenidos exitosamente',
      data: rows
    }
    res.status(200).json(data);
  } catch (error) {
    console.error('Error en getAllDevices:', error);
    res.status(500).json({
      error: 'Error interno del servidor',
      message: error.message
    });
  }
};

const registerDevice = async (req, res) => {
  try {
    const { id_dispositivo, id_usuario, nombre_entrada, total_pagado } = req.body;

    await pool.query(
      'CALL sp_insert_ingresoBLE(?, ?, ?, ?)',
      [id_dispositivo, id_usuario, nombre_entrada, total_pagado || 0.00]
    );

    const [rows] = await pool.query(
      `SELECT * FROM registros_ingresoBLE 
       WHERE id_usuario = ? 
       ORDER BY fecha_hora_ingreso DESC 
       LIMIT 1`,
      [id_usuario]
    );

    const newRegistro = rows[0];

    try {
      await axios.post(`${ESP32_IP}${ESP32_ENDPOINT}`, {
        action: 'activate_led',
        duration: 3000,
        registro_id: newRegistro.id,
        dispositivo: id_dispositivo
      }, { timeout: 5000 });

      console.log('Comando enviado al ESP32 exitosamente');
    } catch (espError) {
      console.error('Error al comunicarse con el ESP32:', espError.message);
    }

    const data = {
      message: 'Dispositivo registrado exitosamente',
      data: newRegistro
    }

    res.status(201).json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

module.exports = { registerDevice, getAllDevices };
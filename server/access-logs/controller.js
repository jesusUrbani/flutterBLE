const pool = require('../config/db');
const axios = require('axios');

const ESP32_IP = process.env.ESP32_IP || 'http://192.168.0.252';
const ESP32_ENDPOINT = process.env.ESP32_ENDPOINT || '/activate-led';

const completeRegistration = async (req, res) => {
  try {
    const { id_usuario } = req.body;

    const [rows] = await pool.query('CALL sp_finalizar_ingresoBLE(?)', [id_usuario]);

    if (!rows || !rows[0] || rows[0].length === 0 || rows[0][0].id_ingreso === null) {
      return res.status(404).json({ error: `Registro no encontrado para usuario '${id_usuario}'` });
    }

    const resultado = rows[0][0];

    const data = {
      message: 'Registro completado exitosamente',
      data: resultado
    }

    res.status(200).json(data);

  } catch (error) {
    console.error('Error completeRegistration:', error);
    res.status(500).json({ error: 'INTERNAL_SERVER_ERROR' });
  }
}

const registerAccessLog = async (req, res) => {
  try {
    const { id_dispositivo, id_usuario, vehicle_type, nombre_entrada } = req.body;

    console.log('Datos recibidos:', req.body);

    // Llamar al procedure RegistrarIngresoBLE
    const [result] = await pool.query(
      'CALL RegistrarIngresoBLE(?, ?, ?, ?)',
      [id_dispositivo, id_usuario, vehicle_type, nombre_entrada]
    );

    // Obtener el último registro insertado
    const [rows] = await pool.query(
      `SELECT * FROM registros_ingresoBLE 
       WHERE id_usuario = ? 
       ORDER BY fecha_hora_ingreso DESC 
       LIMIT 1`,
      [id_usuario]
    );

    const newRegistro = rows[0];

    // Respuesta exitosa
    res.status(201).json({
      ok: true,
      message: 'Ingreso BLE registrado exitosamente',
      data: newRegistro
    });

  } catch (error) {
    console.error('Error en registerAccessLog:', error);
    res.status(500).json({ 
      ok: false,
      message: 'INTERNAL_SERVER_ERROR',
      error: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
}

const finalizarIngreso = async (req, res) => {
  try {
    const { id_dispositivo } = req.body;


    // Llamar al procedure FinalizarIngresoBLE
    const [result] = await pool.query(
      'CALL FinalizarIngresoBLE(?)',
      [id_dispositivo]
    );

    // Si el procedure devuelve resultados
    if (result && result[0] && result[0].length > 0) {
      const registroFinalizado = result[0][0];
      
      res.status(200).json({
        ok: true,
        message: 'Ingreso finalizado exitosamente',
        data: registroFinalizado
      });
    } else {
      res.status(404).json({
        ok: false,
        message: 'No hay registros en curso para este dispositivo'
      });
    }

  } catch (error) {
    console.error('❌ Error en finalizarIngreso:', error);
    res.status(500).json({ 
      ok: false,
      message: 'INTERNAL_SERVER_ERROR',
      error: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
}

const getAccessLogs = async (req, res) => {
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
    res.status(500).json({ error: 'INTERNAL_SERVER_ERROR' });
  }
};

module.exports = { completeRegistration, registerAccessLog, getAccessLogs, finalizarIngreso };
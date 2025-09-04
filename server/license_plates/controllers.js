const pool = require('../config/db');



const registerLicensePlate = async (req, res) => {
  try {
    const { id_dispositivo, placas, estado } = req.body;

    const [rows] = await pool.query(
      'CALL sp_insert_placa(?, ?, ?)',
      [id_dispositivo, placas, estado || true]
    );

    const id_usuario_asociado = rows[0][0]?.id_usuario_asociado || null;

    const data = {
      message: 'Placa registrada exitosamente',
      data: {
        placas,
        id_usuario_asociado,
        estado
      }
    }

    res.status(201).json(data);
  } catch (error) {
    if (error.errno === 1452) {
      return res.status(400).json({ error: 'El dispositivo no existe' });
    }
    res.status(500).json({ error: error.message });
  }
};


const reportLicensePlate = async (req, res) => {
  try {
    const { placas, tipo_reporte, descripcion, estado } = req.body;

    const fecha_reporte = new Date(new Date().toLocaleString('en-US', { 
      timeZone: 'America/Mexico_City',
    }));

    await pool.query(
      'INSERT INTO placas_reportadas (placas, tipo_reporte, descripcion, fecha_reporte, estado) VALUES (?, ?, ?, ?, ?)',
      [placas, tipo_reporte, descripcion, fecha_reporte, estado]
    );

    const data = {
      message: 'Placa reportada exitosamente',
      data: {
        placas,
        tipo_reporte,
        descripcion,
        fecha_reporte,
        estado
      }
    }

    res.status(201).json(data);
  } catch (error) {
    console.log(error);
    res.status(500).json({ error: 'Error en el servidor' });
  }
};

module.exports = { registerLicensePlate, reportLicensePlate };
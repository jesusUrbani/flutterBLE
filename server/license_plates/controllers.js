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
    res.status(500).json({ error: error.message });
  }
};

module.exports = { registerLicensePlate };
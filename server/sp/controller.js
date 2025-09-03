const { pool } = require('../config/db');

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
    res.status(500).json({ error: error.message });
  }
}

module.exports = { completeRegistration };
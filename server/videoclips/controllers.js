const pool = require('../config/db');

const registerVideoclip = async (req, res) => {
  try {
    const { id_dispositivo, archivo } = req.body;
    
    const [rows] = await pool.query(
      'CALL sp_insert_videoclip(?, ?)',
      [id_dispositivo, archivo]
    );

    const id_usuario_asociado = rows[0][0]?.id_usuario_asociado || null;

    const data = {
      message: 'Videoclip registrado exitosamente',
      data: {
        archivo,
        id_usuario_asociado
      }
    }

    res.status(201).json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

module.exports = { registerVideoclip };
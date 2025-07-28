const pool = require('../config/db');

exports.getAllRegistros = async (req, res) => {
    try {
        const [rows] = await pool.query('SELECT * FROM registros_ingreso ORDER BY fecha_hora_ingreso DESC');
        res.json(rows);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
};

exports.createRegistro = async (req, res) => {
    try {
        const { id_dispositivo, nombre_entrada } = req.body;
        
        if (!id_dispositivo || !nombre_entrada) {
            return res.status(400).json({ error: 'id_dispositivo y nombre_entrada son requeridos' });
        }

        const [result] = await pool.query(
            'INSERT INTO registros_ingreso (id_dispositivo, nombre_entrada) VALUES (?, ?)',
            [id_dispositivo, nombre_entrada]
        );
        
        const [newRegistro] = await pool.query('SELECT * FROM registros_ingreso WHERE id = ?', [result.insertId]);
        res.status(201).json(newRegistro[0]);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
};

exports.getRegistroById = async (req, res) => {
    try {
        const [rows] = await pool.query('SELECT * FROM registros_ingreso WHERE id = ?', [req.params.id]);
        
        if (rows.length === 0) {
            return res.status(404).json({ error: 'Registro no encontrado' });
        }
        
        res.json(rows[0]);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
};

exports.deleteRegistro = async (req, res) => {
    try {
        const [result] = await pool.query('DELETE FROM registros_ingreso WHERE id = ?', [req.params.id]);
        
        if (result.affectedRows === 0) {
            return res.status(404).json({ error: 'Registro no encontrado' });
        }
        
        res.status(204).send();
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
};
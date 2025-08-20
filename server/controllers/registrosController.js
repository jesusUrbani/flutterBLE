const pool = require('../config/db');
const axios = require('axios'); // Necesitarás instalar axios: npm install axios

// Configuración del ESP32 (ajusta con la IP correcta de tu ESP32)
const ESP32_IP = 'http://192.168.31.201'; // Cambia por la IP real de tu ESP32
const ESP32_ENDPOINT = '/activate-led';


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
         // ✅ DESPUÉS de insertar en la BD, enviar comando al ESP32
        try {
            await axios.post(`${ESP32_IP}${ESP32_ENDPOINT}`, {
                action: 'activate_led',
                duration: 3000, // 3 segundos
                registro_id: result.insertId,
                dispositivo: id_dispositivo
            }, {
                timeout: 5000 // Timeout de 5 segundos
            });
            
            console.log('Comando enviado al ESP32 exitosamente');
        } catch (espError) {
            console.error('Error al comunicarse con el ESP32:', espError.message);
            // No fallamos la petición principal solo por esto
        }
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
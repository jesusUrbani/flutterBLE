const pool = require('../config/db');
const axios = require('axios');

// Configuración del ESP32 (ajusta con la IP correcta de tu ESP32)
const ESP32_IP = 'http://192.168.0.252';
const ESP32_ENDPOINT = '/activate-led';

/**
 * Obtener todos los ingresos BLE
 */
exports.getAllRegistros = async (req, res) => {
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
        
        res.json(rows);
    } catch (error) {
        console.error('Error en getAllRegistros:', error);
        res.status(500).json({ 
            error: 'Error interno del servidor',
            message: error.message 
        });
    }
};

/**
 * Crear registro de ingreso BLE usando SP
 */
exports.createRegistro = async (req, res) => {
    try {
        const { id_dispositivo, id_usuario, nombre_entrada, total_pagado } = req.body;

        if (!id_dispositivo || !id_usuario || !nombre_entrada) {
            return res.status(400).json({ error: 'id_dispositivo, id_usuario y nombre_entrada son requeridos' });
        }

        // Ejecutar procedimiento almacenado
        await pool.query(
            'CALL sp_insert_ingresoBLE(?, ?, ?, ?)',
            [id_dispositivo, id_usuario, nombre_entrada, total_pagado || 0.00]
        );

        // Obtener último ingreso del usuario (el recién creado)
        const [rows] = await pool.query(
            `SELECT * FROM registros_ingresoBLE 
             WHERE id_usuario = ? 
             ORDER BY fecha_hora_ingreso DESC 
             LIMIT 1`,
            [id_usuario]
        );

        const newRegistro = rows[0];

        // ✅ Enviar comando al ESP32 después de registrar
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

        res.status(201).json(newRegistro);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
};



/**
 * Registrar placa usando SP
 */
exports.createPlaca = async (req, res) => {
    try {
        const { id_dispositivo, placas, estado } = req.body;

        if (!id_dispositivo || !placas) {
            return res.status(400).json({ error: 'id_dispositivo y placas son requeridos' });
        }

        const [rows] = await pool.query(
            'CALL sp_insert_placa(?, ?, ?)',
            [id_dispositivo, placas, estado || true]
        );

        // El SP retorna id_usuario_asociado
        const id_usuario_asociado = rows[0][0]?.id_usuario_asociado || null;

        res.status(201).json({
            mensaje: 'Placa registrada exitosamente',
            placas,
            id_usuario_asociado
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
};

/**
 * Registrar videoclip usando SP
 */
exports.createVideoclip = async (req, res) => {
    try {
        const { id_dispositivo, archivo } = req.body;

        if (!id_dispositivo || !archivo) {
            return res.status(400).json({ error: 'id_dispositivo y archivo son requeridos' });
        }

        const [rows] = await pool.query(
            'CALL sp_insert_videoclip(?, ?)',
            [id_dispositivo, archivo]
        );

        const id_usuario_asociado = rows[0][0]?.id_usuario_asociado || null;

        res.status(201).json({
            mensaje: 'Videoclip registrado exitosamente',
            archivo,
            id_usuario_asociado
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
};

/**
 * Finalizar ingreso BLE usando SP
 */
exports.finalizarIngreso = async (req, res) => {
    try {
        const { id_usuario } = req.body;

        if (!id_usuario) {
            return res.status(400).json({ error: 'id_usuario es requerido' });
        }

        // Trim y string por seguridad
        const usuarioTrim = id_usuario.toString().trim();

        // Ejecutar SP
        const [rows] = await pool.query('CALL sp_finalizar_ingresoBLE(?)', [usuarioTrim]);

        // mysql2 retorna un array de resultados, el SP retorna datos en rows[0]
        if (!rows || !rows[0] || rows[0].length === 0 || rows[0][0].id_ingreso === null) {
            return res.status(404).json({ error: `Registro no encontrado para usuario '${usuarioTrim}'` });
        }

        // SP retorna: id_ingreso, id_usuario, total_pagado, estado
        const resultado = rows[0][0];

        res.json({
            mensaje: 'Ingreso finalizado exitosamente',
            datos: resultado
        });

    } catch (error) {
        console.error('Error finalizar ingreso:', error);
        res.status(500).json({ error: error.message });
    }
};

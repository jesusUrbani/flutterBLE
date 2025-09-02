const express = require('express');
const router = express.Router();
const registrosController = require('../controllers/controller');

// Rutas para registros BLE
router.get('/', registrosController.getAllRegistros);
router.post('/', registrosController.createRegistro);

// Placas y videos
router.post('/placas', registrosController.createPlaca);
router.post('/videoclips', registrosController.createVideoclip);

// Finalizar ingreso
router.post('/finalizar', registrosController.finalizarIngreso);

module.exports = router;

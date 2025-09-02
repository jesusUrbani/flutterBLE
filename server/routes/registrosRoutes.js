const express = require('express');
const router = express.Router();
const registrosController = require('../controllers/registrosController');

router.get('/', registrosController.getAllRegistros);
router.post('/', registrosController.createRegistro);
router.get('/:id', registrosController.getRegistroById);
router.delete('/:id', registrosController.deleteRegistro);
router.post('/placas', registrosController.createPlaca);

module.exports = router;
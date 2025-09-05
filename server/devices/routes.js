const router = require('express').Router();
const { body } = require('express-validator');
const validatorMiddleware = require('../common/middlewares/validator');
const { registerDevice, getAllDevices } = require('./controllers');


router.get('/', [
    getAllDevices
]);

router.post('/', [
    body('id_dispositivo').trim().notEmpty().withMessage('id_dispositivo es requerido'),
    body('id_zona').trim().notEmpty().withMessage('id_zona es requerido'),
    body('nombre_dispositivo').trim().notEmpty().withMessage('nombre_dispositivo es requerido'),
    body('tipo_dispositivo').trim().notEmpty().withMessage('tipo_dispositivo es requerido').isIn(['BLE', 'CAMARA', 'LECTOR_PLACAS']),
    validatorMiddleware,
    registerDevice
]);


module.exports = router;
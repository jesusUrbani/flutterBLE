const router = require('express').Router();
const { body } = require('express-validator');
const validatorMiddleware = require('../common/middlewares/validator');
const { registerDevice, getAllDevices } = require('./controllers');


router.get('/', [
    getAllDevices
]);

router.post('/', [
    body('id_dispositivo').trim().notEmpty().withMessage('id_dispositivo es requerido'),
    body('id_usuario').trim().notEmpty().withMessage('id_usuario es requerido'),
    body('nombre_entrada').trim().notEmpty().withMessage('nombre_entrada es requerido'),
    body('total_pagado').isFloat({ min: 0, max: 9999999999.99 }).withMessage('total_pagado debe ser un número'),
    validatorMiddleware,
    registerDevice
]);

module.exports = router;
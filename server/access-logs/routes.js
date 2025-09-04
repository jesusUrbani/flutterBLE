const router = require('express').Router();
const { body } = require('express-validator');
const validatorMiddleware = require('../common/middlewares/validator');
const { completeRegistration, registerAccessLog, getAccessLogs } = require('./controller');

router.put('/', [
    body('id_usuario').trim().notEmpty().withMessage('id_usuario es requerido'),
    validatorMiddleware,
    completeRegistration
]);

router.post('/', [
    body('id_usuario').trim().notEmpty().withMessage('id_usuario es requerido'),
    body('id_dispositivo').trim().notEmpty().withMessage('id_dispositivo es requerido'),
    body('nombre_entrada').trim().notEmpty().withMessage('nombre_entrada es requerido'),
    body('total_pagado').isFloat().withMessage('total_pagado debe ser un número'),
    validatorMiddleware,
    registerAccessLog
]);

router.get('/', [
    getAccessLogs
]);

module.exports = router;
const router = require('express').Router();
const { body } = require('express-validator');
const validatorMiddleware = require('../common/middlewares/validator');
const { completeRegistration, registerAccessLog, finalizarIngreso, getAccessLogs } = require('./controller');

router.put('/', [
    body('id_usuario').trim().notEmpty().withMessage('id_usuario es requerido'),
    validatorMiddleware,
    completeRegistration
]);

router.post('/registrar-ingreso', [
    body('id_usuario').trim().notEmpty().withMessage('id_usuario es requerido'),
    body('id_dispositivo').trim().notEmpty().withMessage('id_dispositivo es requerido'),
    body('vehicle_type').trim().notEmpty().withMessage('vehicle_type es requerido'),
    body('nombre_entrada').trim().notEmpty().withMessage('nombre_entrada es requerido'),
    validatorMiddleware,
    registerAccessLog
]);

// Marcar salida/finalizado por id_dispositivo
router.post('/finalizar-ingreso', [
    body('id_dispositivo').trim().notEmpty().withMessage('id_dispositivo es requerido'),
    validatorMiddleware,
    finalizarIngreso
]);



router.get('/', [
    getAccessLogs
]);

module.exports = router;
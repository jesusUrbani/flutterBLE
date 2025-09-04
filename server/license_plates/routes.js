const { registerLicensePlate, reportLicensePlate } = require('./controllers');
const { body } = require('express-validator');
const validatorMiddleware = require('../common/middlewares/validator');

const router = require('express').Router();


router.post('/report', [
    body('placas').trim().notEmpty().withMessage('placas es requerido'),
    body('tipo_reporte').trim().notEmpty().withMessage('tipo_reporte es requerido').isIn(['BLOQUEADO', 'ALERTA_SEGURIDAD']).withMessage('tipo_reporte debe ser BLOQUEADO o ALERTA_SEGURIDAD'),
    body('descripcion').trim().notEmpty().withMessage('descripcion es requerido'),
    body('estado').trim().notEmpty().withMessage('estado es requerido').isIn(['ACTIVA', 'RESUELTA', 'CANCELADA']).withMessage('estado debe ser ACTIVA, RESUELTA o CANCELADA'),
    validatorMiddleware,
    reportLicensePlate
]);

router.post('/', [
    body('id_dispositivo').trim().notEmpty().withMessage('id_dispositivo es requerido'),
    body('placas').trim().notEmpty().withMessage('placas es requerido'),
    body('estado').isBoolean().withMessage('estado debe ser un booleano'),
    validatorMiddleware,
    registerLicensePlate
]);

module.exports = router;
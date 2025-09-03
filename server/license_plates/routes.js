const { registerLicensePlate } = require('./controllers');
const { body } = require('express-validator');
const validatorMiddleware = require('../common/middlewares/validator');

const router = require('express').Router();

router.get('/', (req, res) => {
    res.send('Hello World');
});

router.post('/', [
    body('id_dispositivo').trim().notEmpty().withMessage('id_dispositivo es requerido'),
    body('placas').trim().notEmpty().withMessage('placas es requerido'),
    body('estado').isBoolean().withMessage('estado debe ser un booleano'),
    validatorMiddleware,
    registerLicensePlate
]);

module.exports = router;
const router = require('express').Router();
const { body } = require('express-validator');
const validatorMiddleware = require('../common/middlewares/validator');
const { registerVideoclip } = require('./controllers');

router.post('/', [
    body('id_dispositivo').trim().notEmpty().withMessage('id_dispositivo es requerido'),
    body('archivo').trim().notEmpty().withMessage('archivo es requerido'),
    validatorMiddleware,
    registerVideoclip
]);

module.exports = router;

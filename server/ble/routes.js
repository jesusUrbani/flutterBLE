const router = require('express').Router();
const { body } = require('express-validator');
const validatorMiddleware = require('../common/middlewares/validator');
const { completeRegistration } = require('./controller');

router.put('/', [
    body('id_usuario').trim().notEmpty().withMessage('id_usuario es requerido'),
    validatorMiddleware,
    completeRegistration
]);

module.exports = router;
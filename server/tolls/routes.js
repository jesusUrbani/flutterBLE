const router = require('express').Router();
const { body } = require('express-validator');
const validatorMiddleware = require('../common/middlewares/validator');
const { createToll } = require('./controller');

router.post('/', [
    body('name').trim().notEmpty().withMessage('name is required'),
    validatorMiddleware,
    createToll
]);

module.exports = router;
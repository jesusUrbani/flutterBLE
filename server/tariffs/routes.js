const router = require('express').Router();
const { query, body } = require('express-validator');
const { getTariff, createTariff } = require('./controller');
const validatorMiddleware = require('../common/middlewares/validator');

router.get('/', [
    query('toll_id').notEmpty().withMessage('toll_id is required').isInt().withMessage('toll_id must be an integer'),
    query('vehicle_type').notEmpty().withMessage('vehicle_type is required').isString().withMessage('vehicle_type must be a string'),
    validatorMiddleware,
    getTariff
]);

router.post('/', [
    body('toll_id').notEmpty().withMessage('toll_id is required').isInt().withMessage('toll_id must be an integer'),
    body('vehicle_type').notEmpty().withMessage('vehicle_type is required').isString().withMessage('vehicle_type must be a string'),
    body('tariff').notEmpty().withMessage('tariff is required').isFloat().withMessage('tariff must be a float'),
    validatorMiddleware,
    createTariff
]);

/*
router.put('/', [
    body('id').notEmpty().withMessage('id is required').isInt().withMessage('id must be an integer'),
    body('tariff').notEmpty().withMessage('tariff is required').isFloat().withMessage('tariff must be a float'),
    validatorMiddleware,
    updateTariff
]);
*/

module.exports = router;
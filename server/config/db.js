const mysql = require('mysql2/promise');

const pool = mysql.createPool({
    host: 'localhost',
    user: 'root', // Cambia por tu usuario de MySQL
    password: '', // Cambia por tu contraseña de MySQL
    database: 'control_acceso',
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0
});

module.exports = pool;
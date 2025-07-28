const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const registrosRoutes = require('./routes/registrosRoutes');

const app = express();

// Middlewares
app.use(cors());
app.use(bodyParser.json());

// Rutas
app.use('/api/registros', registrosRoutes);

// Manejo de errores
app.use((err, req, res, next) => {
    console.error(err.stack);
    res.status(500).json({ error: 'Algo salió mal!' });
});

// Iniciar servidor
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`Servidor corriendo en http://localhost:${PORT}`);
});
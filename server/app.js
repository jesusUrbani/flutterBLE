const express = require('express');
const cors = require('cors');
const accessLogsRoutes = require('./access-logs/routes');
const devicesRoutes = require('./devices/routes');
const licensePlatesRoutes = require('./license_plates/routes');
const videoclipsRoutes = require('./videoclips/routes');
const tariffsRoutes = require('./tariffs/routes');
const tollsRoutes = require('./tolls/routes');

const app = express();

// Middlewares
app.use(cors());
app.use(express.json());

// Rutas
app.use('/api/access-logs', accessLogsRoutes);
app.use('/api/devices', devicesRoutes);
app.use('/api/license_plates', licensePlatesRoutes);
app.use('/api/videoclips', videoclipsRoutes);
app.use('/api/tariffs', tariffsRoutes);
app.use('/api/tolls', tollsRoutes);


// Iniciar servidor
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`Servidor corriendo en http://localhost:${PORT}`);
});
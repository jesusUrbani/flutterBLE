
-- Crear la base de datos si no existe
CREATE DATABASE IF NOT EXISTS control_acceso;
USE control_acceso;

-- Crear la tabla básica para guardar ingresos
CREATE TABLE IF NOT EXISTS registros_ingreso (
    id INT AUTO_INCREMENT PRIMARY KEY,
    id_dispositivo VARCHAR(50) NOT NULL,
    nombre_entrada VARCHAR(100) NOT NULL,
    fecha_hora_ingreso DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Ejemplo de inserción de datos
INSERT INTO registros_ingreso (id_dispositivo, nombre_entrada) 
VALUES ('DISP-001', 'Juan Pérez');

-- Consulta para obtener los registros
SELECT * FROM registros_ingreso ORDER BY fecha_hora_ingreso DESC;

CREATE TABLE IF NOT EXISTS tolls (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT unique_name UNIQUE (name)
);


CREATE TABLE IF NOT EXISTS tariffs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  toll_id INT NOT NULL,
  vehicle_type VARCHAR(50) NOT NULL,
  tariff DECIMAL(10, 2) NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (toll_id) REFERENCES tolls(id) ON DELETE RESTRICT,
  CONSTRAINT unique_toll_vehicle_type UNIQUE (toll_id, vehicle_type)
);



CREATE TABLE IF NOT EXISTS dispositivos (
    id_dispositivo VARCHAR(50) PRIMARY KEY,
	toll_id INT NOT NULL,
    nombre_dispositivo VARCHAR(100) NOT NULL,
    tipo_dispositivo ENUM('BLE', 'CAMARA', 'LECTOR_PLACAS') NOT NULL,
    fecha_instalacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    estado BOOL NOT NULL DEFAULT TRUE,
    ultima_actualizacion DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	FOREIGN KEY (toll_id) REFERENCES tolls(id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS registros_ingresoBLE (
    id INT AUTO_INCREMENT PRIMARY KEY,
    id_dispositivo VARCHAR(50) NOT NULL,
    id_usuario VARCHAR(50) NOT NULL,
    vehicle_type VARCHAR(50) NOT NULL,  -- ¡Este campo SÍ es necesario!
    nombre_entrada VARCHAR(100) NOT NULL,
    fecha_hora_ingreso DATETIME DEFAULT CURRENT_TIMESTAMP,
    estado ENUM('EN_CURSO', 'FINALIZADO') DEFAULT 'EN_CURSO',
    FOREIGN KEY (id_dispositivo) REFERENCES dispositivos(id_dispositivo) ON DELETE RESTRICT
);

DELIMITER $$

CREATE PROCEDURE RegistrarIngresoBLE(
    IN p_id_dispositivo VARCHAR(50),
    IN p_id_usuario VARCHAR(50),
    IN p_vehicle_type VARCHAR(50),
    IN p_nombre_entrada VARCHAR(100)
)
BEGIN
    -- Insertar el registro con estado 'EN_CURSO' por defecto
    INSERT INTO registros_ingresoBLE (
        id_dispositivo,
        id_usuario,
        vehicle_type,
        nombre_entrada
    ) VALUES (
        p_id_dispositivo,
        p_id_usuario,
        p_vehicle_type,
        p_nombre_entrada
    );
    
    -- Opcional: Devolver el ID del registro insertado
    SELECT LAST_INSERT_ID() as id_registro;
END$$

DELIMITER ;


DELIMITER $$

CREATE PROCEDURE FinalizarIngresoBLE(
    IN p_id_dispositivo VARCHAR(50)
)
BEGIN
    -- Variables para controlar el proceso
    DECLARE v_last_id INT;
    DECLARE v_count INT;
    
    -- Contar registros en curso para este dispositivo
    SELECT COUNT(*) INTO v_count 
    FROM registros_ingresoBLE 
    WHERE id_dispositivo = p_id_dispositivo 
    AND estado = 'EN_CURSO';
    
    -- Si no hay registros en curso, mostrar mensaje
    IF v_count = 0 THEN
        SELECT 'NO_HAY_REGISTROS' as resultado, 
               'No hay registros en curso para este dispositivo' as mensaje;
    ELSE
        -- Obtener el último registro en curso para este dispositivo
        SELECT id INTO v_last_id 
        FROM registros_ingresoBLE 
        WHERE id_dispositivo = p_id_dispositivo 
        AND estado = 'EN_CURSO' 
        ORDER BY fecha_hora_ingreso DESC 
        LIMIT 1;
        
        -- Marcar el último registro como FINALIZADO
        UPDATE registros_ingresoBLE 
        SET estado = 'FINALIZADO', 
            fecha_hora_ingreso = fecha_hora_ingreso  -- Mantiene la fecha original
        WHERE id = v_last_id;
        
        -- Devolver información del registro finalizado
        SELECT 
            'FINALIZADO' as resultado,
            id as id_registro,
            id_dispositivo,
            id_usuario,
            vehicle_type,
            nombre_entrada,
            fecha_hora_ingreso
        FROM registros_ingresoBLE 
        WHERE id = v_last_id;
    END IF;
END$$

DELIMITER ;


INSERT IGNORE INTO tolls (name) VALUES ('Caseta 1'), ('Casetas 2'), ('Casetas 3');
INSERT IGNORE INTO tariffs (toll_id, vehicle_type, tariff) VALUES 
(1, 'MOTO', 10),
(1, 'CARRO', 20),
(1, 'CAMIONETA', 30),
(2, 'MOTO', 15),
(2, 'CARRO', 25),
(2, 'CAMIONETA', 35);


drop table registros_ingresoBLE;

-- Vaciar la tabla dispositivos
TRUNCATE TABLE dispositivos;

-- Insertar solo UN dispositivo BLE por cada caseta
INSERT IGNORE INTO dispositivos (id_dispositivo, toll_id, nombre_dispositivo, tipo_dispositivo) VALUES
('BLE_CASETA1', 1, 'Dispositivo BLE Caseta 1', 'BLE'),
('BLE_CASETA2', 2, 'Dispositivo BLE Caseta 2', 'BLE'),
('BLE_CASETA3', 3, 'Dispositivo BLE Caseta 3', 'BLE');


-- Dispositivos con sus tarifas disponibles
SELECT 
    d.id_dispositivo,
    d.nombre_dispositivo,
    t.name as peaje,
    tar.vehicle_type,
    tar.tariff as tarifa
FROM dispositivos d
INNER JOIN tolls t ON d.toll_id = t.id
INNER JOIN tariffs tar ON d.toll_id = tar.toll_id
WHERE d.estado = TRUE
ORDER BY t.name, tar.vehicle_type;
-- Ver todos los peajes (tolls)
SELECT * FROM tolls;

-- Ver todas las tarifas (tariffs)
SELECT * FROM tariffs;

SELECT * FROM dispositivos;


SELECT * FROM registros_ingresoBLE;


-- Tarifas con nombres de peajes
SELECT 
    t.name as peaje,
    tr.vehicle_type as tipo_vehiculo,
    tr.tariff as tarifa,
    tr.created_at
FROM tariffs tr
INNER JOIN tolls t ON tr.toll_id = t.id
ORDER BY t.name, tr.vehicle_type;


SELECT 
    r.id,
    r.id_usuario,
    r.vehicle_type as tipo_vehiculo,
    r.nombre_entrada,
    r.fecha_hora_ingreso,
    r.estado,
    d.nombre_dispositivo,
    t.name as nombre_caseta,
    t.id as id_caseta,
    tar.tariff as costo_tarifa,
    CONCAT('$', FORMAT(tar.tariff, 2)) as costo_formateado
FROM registros_ingresoBLE r
INNER JOIN dispositivos d ON r.id_dispositivo = d.id_dispositivo
INNER JOIN tolls t ON d.toll_id = t.id
INNER JOIN tariffs tar ON d.toll_id = tar.toll_id AND r.vehicle_type = tar.vehicle_type
ORDER BY r.fecha_hora_ingreso DESC;
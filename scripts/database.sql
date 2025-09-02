
-- Crear la base de datos si no existe
CREATE DATABASE IF NOT EXISTS control_acceso;
USE control_acceso;

CREATE TABLE IF NOT EXISTS zona (
    id_zona VARCHAR(50) PRIMARY KEY,
    nombre_zona VARCHAR(100) NOT NULL,
    fecha_instalacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    estado BOOL NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS dispositivos (
    id_dispositivo VARCHAR(50) PRIMARY KEY,
	id_zona VARCHAR(50) NOT NULL ,
    nombre_dispositivo VARCHAR(100) NOT NULL,
    tipo_dispositivo ENUM('BLE', 'CAMARA', 'LECTOR_PLACAS') NOT NULL,
    fecha_instalacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    estado BOOL NOT NULL DEFAULT TRUE,
    ultima_actualizacion DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	FOREIGN KEY (id_zona) REFERENCES zona(id_zona) ON DELETE RESTRICT
);

--  registros_ingresoBLE
CREATE TABLE IF NOT EXISTS registros_ingresoBLE (
    id INT AUTO_INCREMENT PRIMARY KEY,
    id_dispositivo VARCHAR(50) NOT NULL,
    id_usuario VARCHAR(50) NOT NULL,
    total_pagado DECIMAL(10, 2) DEFAULT 0.00,  -- Nuevo campo agregado
    nombre_entrada VARCHAR(100) NOT NULL,
    fecha_hora_ingreso DATETIME DEFAULT CURRENT_TIMESTAMP,
    estado ENUM('EN_CURSO','FINALIZADO') DEFAULT 'EN_CURSO',
    FOREIGN KEY (id_dispositivo) REFERENCES dispositivos(id_dispositivo) ON DELETE RESTRICT
);

--  registros_placas
CREATE TABLE IF NOT EXISTS registros_placas (
    id INT AUTO_INCREMENT PRIMARY KEY,
	id_ingreso INT  NULL,
    id_dispositivo VARCHAR(50) NOT NULL,
    placas VARCHAR(15) NOT NULL,
    estado BOOL NOT NULL,
    fecha_hora_ingreso DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_dispositivo) REFERENCES dispositivos(id_dispositivo) ON DELETE RESTRICT,
    FOREIGN KEY (id_ingreso) REFERENCES registros_ingresoBLE(id),
    INDEX idx_placas (placas),
    INDEX idx_fecha_placas (fecha_hora_ingreso)
);

--  registros_videoclips
CREATE TABLE IF NOT EXISTS registros_videoclips (
    id INT AUTO_INCREMENT PRIMARY KEY,
   	id_ingreso INT NULL,
    id_dispositivo VARCHAR(50) NOT NULL,
    archivo VARCHAR(255),
    fecha_hora_ingreso DATETIME DEFAULT CURRENT_TIMESTAMP,
    estado BOOL NOT NULL DEFAULT TRUE,
    FOREIGN KEY (id_dispositivo) REFERENCES dispositivos(id_dispositivo) ON DELETE RESTRICT,
    FOREIGN KEY (id_ingreso) REFERENCES registros_ingresoBLE(id),
    INDEX idx_fecha_video (fecha_hora_ingreso)
);


CREATE TABLE IF NOT EXISTS placas_reportadas (
    id INT AUTO_INCREMENT PRIMARY KEY,
    placas VARCHAR(15) NOT NULL,
    tipo_reporte ENUM( 'BLOQUEADO', 'ALERTA_SEGURIDAD') NOT NULL,
    descripcion TEXT,
    fecha_reporte DATETIME DEFAULT CURRENT_TIMESTAMP,
    estado ENUM('ACTIVA', 'RESUELTA', 'CANCELADA') DEFAULT 'ACTIVA',

    
    -- Índices para búsquedas eficientes
    INDEX idx_placas_reportadas (placas),
    INDEX idx_estado_reporte (estado),
    INDEX idx_tipo_reporte (tipo_reporte),
    INDEX idx_fecha_reporte (fecha_reporte),
    
    -- Para búsquedas combinadas
    INDEX idx_placas_estado (placas, estado),
    INDEX idx_tipo_estado (tipo_reporte, estado)
);
 
--  procedures


DELIMITER $$

CREATE PROCEDURE sp_insert_ingresoBLE (
    IN p_id_dispositivo VARCHAR(50),
    IN p_id_usuario VARCHAR(50),
    IN p_nombre_entrada VARCHAR(100),
    IN p_total_pagado DECIMAL(10, 2) 
)
BEGIN
    INSERT INTO registros_ingresoBLE (id_dispositivo, id_usuario, nombre_entrada, total_pagado)
    VALUES (p_id_dispositivo, p_id_usuario, p_nombre_entrada, p_total_pagado);
END $$

DELIMITER ;


DELIMITER $$

CREATE PROCEDURE sp_insert_placa (
    IN p_id_dispositivo VARCHAR(50),
    IN p_placas VARCHAR(15),
    IN p_estado BOOL
)
BEGIN
    DECLARE v_id_zona VARCHAR(50);
    DECLARE v_id_ingreso INT;
    DECLARE v_id_usuario VARCHAR(50);

    -- 1. Buscar zona del dispositivo de placa
    SELECT id_zona INTO v_id_zona 
    FROM dispositivos 
    WHERE id_dispositivo = p_id_dispositivo;

    -- 2. Buscar el ingreso BLE activo MÁS RECIENTE en la misma zona
    SELECT r.id, r.id_usuario INTO v_id_ingreso, v_id_usuario
    FROM registros_ingresoBLE r
    JOIN dispositivos d ON r.id_dispositivo = d.id_dispositivo
    WHERE d.id_zona = v_id_zona 
      AND r.estado = 'EN_CURSO'
    ORDER BY r.fecha_hora_ingreso DESC 
    LIMIT 1;

    -- 3. Insertar registro de placa (asocia usuario si existe)
    INSERT INTO registros_placas (id_dispositivo, placas, estado, id_ingreso)
    VALUES (p_id_dispositivo, p_placas, p_estado, v_id_ingreso);

    -- 4. RETORNAR el ID de usuario si se necesita en la aplicación
    SELECT v_id_usuario AS id_usuario_asociado;
END $$

DELIMITER ;


DELIMITER $$

CREATE PROCEDURE sp_insert_videoclip (
    IN p_id_dispositivo VARCHAR(50),
    IN p_archivo VARCHAR(255)
)
BEGIN
    DECLARE v_id_zona VARCHAR(50);
    DECLARE v_id_ingreso INT;
    DECLARE v_id_usuario VARCHAR(50);

    -- 1. Buscar zona de la cámara
    SELECT id_zona INTO v_id_zona 
    FROM dispositivos 
    WHERE id_dispositivo = p_id_dispositivo;

    -- 2. Buscar el ingreso BLE activo MÁS RECIENTE en la misma zona
    SELECT r.id, r.id_usuario INTO v_id_ingreso, v_id_usuario
    FROM registros_ingresoBLE r
    JOIN dispositivos d ON r.id_dispositivo = d.id_dispositivo
    WHERE d.id_zona = v_id_zona 
      AND r.estado = 'EN_CURSO'
    ORDER BY r.fecha_hora_ingreso DESC 
    LIMIT 1;

    -- 3. Insertar videoclip (asocia usuario si existe)
    INSERT INTO registros_videoclips (id_dispositivo, archivo, id_ingreso)
    VALUES (p_id_dispositivo, p_archivo, v_id_ingreso);

    -- 4. RETORNAR el ID de usuario si se necesita en la aplicación
    SELECT v_id_usuario AS id_usuario_asociado;
END $$

DELIMITER ;

DELIMITER $$

CREATE PROCEDURE sp_finalizar_ingresoBLE (
    IN p_id_usuario VARCHAR(50)
)
BEGIN
    -- Obtener información antes de actualizar
    SELECT id, total_pagado INTO @v_id_ingreso, @v_total_pagado
    FROM registros_ingresoBLE 
    WHERE id_usuario = p_id_usuario 
      AND estado = 'EN_CURSO';
    
    -- Actualizar estado
    UPDATE registros_ingresoBLE 
    SET estado = 'FINALIZADO'
    WHERE id_usuario = p_id_usuario 
      AND estado = 'EN_CURSO';
    
    -- Retornar información del pago
    SELECT 
        @v_id_ingreso AS id_ingreso,
        p_id_usuario AS id_usuario,
        @v_total_pagado AS total_pagado,
        'INGRESO_FINALIZADO' AS estado;
END $$

DELIMITER ;


-- Insertar zonas
INSERT INTO zona (id_zona, nombre_zona) VALUES 
('ZONA_NORTE', 'Carretera colombia'),
('ZONA_SUR', 'Carretera nacional '),
('ZONA_CENTRO', 'Carretera monterrey saltillo');

-- Insertar dispositivos
INSERT INTO dispositivos (id_dispositivo, id_zona, nombre_dispositivo, tipo_dispositivo) VALUES 
('BLE_NORTE_01', 'ZONA_NORTE', 'Lector BLE Entrada Norte', 'BLE'),
('BLE_SUR_01', 'ZONA_SUR', 'Lector BLE Entrada Sur', 'BLE'),
('CAM_NORTE_01', 'ZONA_NORTE', 'Cámara Vigilancia Norte', 'CAMARA'),
('CAM_SUR_01', 'ZONA_SUR', 'Cámara Vigilancia Sur', 'CAMARA'),
('LEC_PLACAS_01', 'ZONA_NORTE', 'Lector Placas Norte', 'LECTOR_PLACAS'),
('LEC_PLACAS_02', 'ZONA_SUR', 'Lector Placas Sur', 'LECTOR_PLACAS');

-- Usuario ingresa por Norte SIN pago inicial
CALL sp_insert_ingresoBLE('BLE_NORTE_01', 'USR_001', 'Entrada Principal Norte', 0.00);

-- Usuario ingresa por Sur CON pago de $50
CALL sp_insert_ingresoBLE('BLE_SUR_01', 'USR_002', 'Entrada Secundaria Sur', 50.00);

-- Usuario ingresa por Norte CON pago de $30
CALL sp_insert_ingresoBLE('BLE_NORTE_01', 'USR_003', 'Entrada Principal Norte', 30.00);

-- Segundo ingreso del mismo usuario (diferente zona)
CALL sp_insert_ingresoBLE('BLE_SUR_01', 'USR_001', 'Entrada Secundaria Sur', 25.00);

-- Placa leída en Norte (asocia con USR_003 que está activo en Norte)
CALL sp_insert_placa('LEC_PLACAS_01', 'ABC123', TRUE);
-- Retorna: id_usuario_asociado = 'USR_003'

-- Placa leída en Sur (asocia con USR_002 que está activo en Sur)  
CALL sp_insert_placa('LEC_PLACAS_02', 'XYZ789', TRUE);
-- Retorna: id_usuario_asociado = 'USR_002'

-- Otra placa en Norte (asocia con USR_003)
CALL sp_insert_placa('LEC_PLACAS_01', 'DEF456', TRUE);
-- Retorna: id_usuario_asociado = 'USR_003'

-- Placa leída SIN usuario activo en la zona
CALL sp_insert_placa('LEC_PLACAS_01', 'GHI789', FALSE);
-- Retorna: id_usuario_asociado = NULL


-- Video grabado en Norte (asocia con USR_003)
CALL sp_insert_videoclip('CAM_NORTE_01', 'video_norte_20241001_1200.mp4');
-- Retorna: id_usuario_asociado = 'USR_003'

-- Video grabado en Sur (asocia con USR_002)
CALL sp_insert_videoclip('CAM_SUR_01', 'video_sur_20241001_1215.mp4');
-- Retorna: id_usuario_asociado = 'USR_002'

-- Video grabado SIN usuario activo
CALL sp_insert_videoclip('CAM_NORTE_01', 'video_norte_20241001_1230.mp4');
-- Retorna: id_usuario_asociado = NULL


-- Finalizar ingreso de USR_002 en Sur
CALL sp_finalizar_ingresoBLE('USR_002');
-- Retorna: id_ingreso, id_usuario, total_pagado, estado

-- Finalizar ingreso de USR_003 en Norte  
CALL sp_finalizar_ingresoBLE('USR_003');
-- Retorna: id_ingreso, id_usuario, total_pagado, estado

-- USR_001 tiene dos ingresos activos, finaliza el más reciente (Sur)
CALL sp_finalizar_ingresoBLE('USR_001');
-- Retorna: id_ingreso del ingreso en Sur



-- Ver ingresos BLE
SELECT * FROM registros_ingresoBLE;

-- Ver placas registradas
SELECT * FROM registros_placas;

-- Ver videos registrados  
SELECT * FROM registros_videoclips;

-- Ver correlaciones (ingresos con placas y videos)
SELECT 
    rib.id_usuario,
    rib.nombre_entrada, 
    rib.total_pagado,
    rib.estado as estado_ingreso,
    rp.placas,
    rv.archivo as video_asociado
FROM registros_ingresoBLE rib
LEFT JOIN registros_placas rp ON rib.id = rp.id_ingreso
LEFT JOIN registros_videoclips rv ON rib.id = rv.id_ingreso;
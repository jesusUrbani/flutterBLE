
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
 
-- ============================================================================
-- ANEXO PUNTO 6 — Modelo COMPLETO normalizado (13 tablas, Punto 2 del TP)
-- ============================================================================
-- NOTA DE ALCANCE (leer antes de ejecutar):
-- El LABORATORIO usó una versión SIMPLIFICADA de 4 tablas (Punto 6):
--   Hotel, Habitacion, Huesped, Reserva.
-- Este anexo es el MODELO COMPLETO del Punto 2 (13 tablas) con teléfonos,
-- correos, domicilios, puntos de interés, tipos de habitación y comodidades
-- normalizados. NO es el esquema sobre el que se cargaron los 6M de filas
-- ni sobre el que corren las consultas de la Parte V/VI.
-- Sintaxis: MariaDB 10.6. Motor InnoDB. Codificación utf8mb4.
-- Orden de creación: padres antes que hijas. FK con ON DELETE CASCADE
-- donde la hija no tiene sentido sin el padre.
-- ============================================================================

CREATE DATABASE IF NOT EXISTS hotel_db
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE hotel_db;

-- ------------------------------------------------------------------
-- 1. HOTEL
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS HOTEL (
    id_hotel INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    ciudad VARCHAR(100) NOT NULL,
    direccion VARCHAR(150) NOT NULL,
    estrellas INT NOT NULL,
    CONSTRAINT chk_hotel_estrellas CHECK (estrellas BETWEEN 1 AND 5)
) ENGINE = InnoDB;

-- ------------------------------------------------------------------
-- 2. TELEFONO_HOTEL (1 hotel -> N teléfonos)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS TELEFONO_HOTEL (
    id_telefono INT AUTO_INCREMENT PRIMARY KEY,
    id_hotel INT NOT NULL,
    telefono VARCHAR(30) NOT NULL,
    CONSTRAINT fk_telhotel_hotel FOREIGN KEY (id_hotel)
        REFERENCES HOTEL (id_hotel) ON DELETE CASCADE,
    CONSTRAINT uq_telhotel UNIQUE (id_hotel, telefono)
) ENGINE = InnoDB;
CREATE INDEX idx_telhotel_hotel ON TELEFONO_HOTEL (id_hotel);

-- ------------------------------------------------------------------
-- 3. CORREO_HOTEL (1 hotel -> N correos)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS CORREO_HOTEL (
    id_correo INT AUTO_INCREMENT PRIMARY KEY,
    id_hotel INT NOT NULL,
    email VARCHAR(100) NOT NULL,
    CONSTRAINT fk_correohotel_hotel FOREIGN KEY (id_hotel)
        REFERENCES HOTEL (id_hotel) ON DELETE CASCADE,
    CONSTRAINT uq_correohotel UNIQUE (id_hotel, email)
) ENGINE = InnoDB;
CREATE INDEX idx_correohotel_hotel ON CORREO_HOTEL (id_hotel);

-- ------------------------------------------------------------------
-- 4. PUNTO_INTERES (catálogo de lugares cercanos)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS PUNTO_INTERES (
    id_punto INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    tipo VARCHAR(50) NOT NULL,
    direccion VARCHAR(150) NOT NULL,
    CONSTRAINT uq_punto UNIQUE (nombre, direccion)
) ENGINE = InnoDB;

-- ------------------------------------------------------------------
-- 5. HOTEL_PUNTO_INTERES (N:M hotel <-> punto de interés)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS HOTEL_PUNTO_INTERES (
    id_hotel INT NOT NULL,
    id_punto INT NOT NULL,
    distancia_m INT NULL,
    PRIMARY KEY (id_hotel, id_punto),
    CONSTRAINT fk_hpi_hotel FOREIGN KEY (id_hotel)
        REFERENCES HOTEL (id_hotel) ON DELETE CASCADE,
    CONSTRAINT fk_hpi_punto FOREIGN KEY (id_punto)
        REFERENCES PUNTO_INTERES (id_punto) ON DELETE CASCADE
) ENGINE = InnoDB;

-- ------------------------------------------------------------------
-- 6. TIPO_HABITACION (catálogo: Simple, Doble, Suite, ...)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS TIPO_HABITACION (
    id_tipo INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE,
    descripcion VARCHAR(255) NULL,
    precio_base DECIMAL(10,2) NOT NULL,
    capacidad INT NOT NULL,
    CONSTRAINT chk_tipo_precio CHECK (precio_base >= 0),
    CONSTRAINT chk_tipo_capacidad CHECK (capacidad >= 1)
) ENGINE = InnoDB;

-- ------------------------------------------------------------------
-- 7. HABITACION
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS HABITACION (
    id_habitacion INT AUTO_INCREMENT PRIMARY KEY,
    id_hotel INT NOT NULL,
    id_tipo INT NOT NULL,
    numero_habitacion VARCHAR(10) NOT NULL,
    precio_noche DECIMAL(10,2) NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'Disponible',
    CONSTRAINT fk_habitacion_hotel FOREIGN KEY (id_hotel)
        REFERENCES HOTEL (id_hotel) ON DELETE CASCADE,
    CONSTRAINT fk_habitacion_tipo FOREIGN KEY (id_tipo)
        REFERENCES TIPO_HABITACION (id_tipo),
    CONSTRAINT uq_habitacion UNIQUE (id_hotel, numero_habitacion),
    CONSTRAINT chk_habitacion_precio CHECK (precio_noche >= 0)
) ENGINE = InnoDB;
CREATE INDEX idx_habitacion_hotel ON HABITACION (id_hotel);
CREATE INDEX idx_habitacion_tipo ON HABITACION (id_tipo);

-- ------------------------------------------------------------------
-- 8. COMODIDAD (catálogo: WiFi, TV, Minibar, ...)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS COMODIDAD (
    id_comodidad INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE,
    descripcion VARCHAR(255) NULL
) ENGINE = InnoDB;

-- ------------------------------------------------------------------
-- 9. HABITACION_COMODIDAD (N:M habitación <-> comodidad)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS HABITACION_COMODIDAD (
    id_habitacion INT NOT NULL,
    id_comodidad INT NOT NULL,
    PRIMARY KEY (id_habitacion, id_comodidad),
    CONSTRAINT fk_hc_habitacion FOREIGN KEY (id_habitacion)
        REFERENCES HABITACION (id_habitacion) ON DELETE CASCADE,
    CONSTRAINT fk_hc_comodidad FOREIGN KEY (id_comodidad)
        REFERENCES COMODIDAD (id_comodidad) ON DELETE CASCADE
) ENGINE = InnoDB;

-- ------------------------------------------------------------------
-- 10. HUESPED
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS HUESPED (
    id_huesped INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(60) NOT NULL,
    apellido VARCHAR(60) NOT NULL,
    dni VARCHAR(20) NOT NULL UNIQUE,
    telefono VARCHAR(30) NULL,
    email VARCHAR(100) NULL UNIQUE
) ENGINE = InnoDB;

-- ------------------------------------------------------------------
-- 11. DOMICILIO_HUESPED (1 huésped -> N domicilios, ej. actual/anterior)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS DOMICILIO_HUESPED (
    id_domicilio INT AUTO_INCREMENT PRIMARY KEY,
    id_huesped INT NOT NULL,
    calle VARCHAR(100) NOT NULL,
    numero VARCHAR(10) NOT NULL,
    ciudad VARCHAR(100) NOT NULL,
    provincia VARCHAR(100) NULL,
    codigo_postal VARCHAR(10) NULL,
    CONSTRAINT fk_dom_huesped FOREIGN KEY (id_huesped)
        REFERENCES HUESPED (id_huesped) ON DELETE CASCADE
) ENGINE = InnoDB;
CREATE INDEX idx_dom_huesped ON DOMICILIO_HUESPED (id_huesped);

-- ------------------------------------------------------------------
-- 12a. TELEFONO_HUESPED (1 huésped -> N teléfonos)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS TELEFONO_HUESPED (
    id_telefono INT AUTO_INCREMENT PRIMARY KEY,
    id_huesped INT NOT NULL,
    telefono VARCHAR(30) NOT NULL,
    CONSTRAINT fk_telhuesped_huesped FOREIGN KEY (id_huesped)
        REFERENCES HUESPED (id_huesped) ON DELETE CASCADE,
    CONSTRAINT uq_telhuesped UNIQUE (id_huesped, telefono)
) ENGINE = InnoDB;
CREATE INDEX idx_telhuesped_huesped ON TELEFONO_HUESPED (id_huesped);

-- ------------------------------------------------------------------
-- 12b. CORREO_HUESPED (1 huésped -> N correos)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS CORREO_HUESPED (
    id_correo INT AUTO_INCREMENT PRIMARY KEY,
    id_huesped INT NOT NULL,
    email VARCHAR(100) NOT NULL,
    CONSTRAINT fk_correohuesped_huesped FOREIGN KEY (id_huesped)
        REFERENCES HUESPED (id_huesped) ON DELETE CASCADE,
    CONSTRAINT uq_correohuesped UNIQUE (id_huesped, email)
) ENGINE = InnoDB;
CREATE INDEX idx_correohuesped_huesped ON CORREO_HUESPED (id_huesped);

-- ------------------------------------------------------------------
-- 13. RESERVA
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RESERVA (
    id_reserva INT AUTO_INCREMENT PRIMARY KEY,
    id_habitacion INT NOT NULL,
    id_huesped INT NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    estado_reserva VARCHAR(30) NOT NULL DEFAULT 'Confirmada',
    tarifa DECIMAL(10,2) NULL,
    CONSTRAINT fk_reserva_habitacion FOREIGN KEY (id_habitacion)
        REFERENCES HABITACION (id_habitacion) ON DELETE CASCADE,
    CONSTRAINT fk_reserva_huesped FOREIGN KEY (id_huesped)
        REFERENCES HUESPED (id_huesped) ON DELETE CASCADE,
    CONSTRAINT chk_reserva_fechas CHECK (fecha_fin > fecha_inicio),
    CONSTRAINT chk_reserva_tarifa CHECK (tarifa IS NULL OR tarifa >= 0)
) ENGINE = InnoDB;
CREATE INDEX idx_reserva_habitacion ON RESERVA (id_habitacion);
CREATE INDEX idx_reserva_huesped ON RESERVA (id_huesped);
CREATE INDEX idx_reserva_fecha ON RESERVA (fecha_inicio);

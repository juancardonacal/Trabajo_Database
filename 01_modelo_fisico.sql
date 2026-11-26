

CREATE TABLE ciudad (
    id_ciudad     NUMBER,
    nombre        VARCHAR2(100) CONSTRAINT nn_ciudad_nombre NOT NULL,
    departamento  VARCHAR2(50),
    poblacion     NUMBER,
    CONSTRAINT pk_ciudad PRIMARY KEY (id_ciudad),
    CONSTRAINT chk_ciudad_poblacion CHECK (poblacion >= 0)
);

CREATE TABLE tipo_vehiculo (
    id_tipo              NUMBER,
    nombre               VARCHAR2(50) CONSTRAINT nn_tipo_nombre NOT NULL,
    descripcion          VARCHAR2(200),
    factor_emision_base  NUMBER(6,4),
    CONSTRAINT pk_tipo_vehiculo PRIMARY KEY (id_tipo),
    CONSTRAINT uq_tipo_nombre UNIQUE (nombre),
    CONSTRAINT chk_tipo_factor CHECK (factor_emision_base > 0)
);

CREATE TABLE combustible (
    id_combustible      NUMBER,
    nombre              VARCHAR2(30) CONSTRAINT nn_comb_nombre NOT NULL,
    factor_co2_teorico  NUMBER(8,4),
    CONSTRAINT pk_combustible PRIMARY KEY (id_combustible),
    CONSTRAINT uq_comb_nombre UNIQUE (nombre)
);

CREATE TABLE propietario (
    id_propietario  NUMBER,
    nombre          VARCHAR2(150) CONSTRAINT nn_prop_nombre NOT NULL,
    tipo_persona    VARCHAR2(10),
    email           VARCHAR2(100),
    CONSTRAINT pk_propietario PRIMARY KEY (id_propietario),
    CONSTRAINT chk_prop_tipo CHECK (tipo_persona IN ('NATURAL', 'JURIDICA')),
    CONSTRAINT uq_prop_email UNIQUE (email)
);





CREATE TABLE vehiculo (
    id_vehiculo      NUMBER,
    placa            VARCHAR2(10) CONSTRAINT nn_veh_placa NOT NULL,
    modelo           VARCHAR2(50),
    año_fabricacion  NUMBER,
    cilindraje       NUMBER,
    id_ciudad        NUMBER CONSTRAINT nn_veh_ciudad NOT NULL,
    id_tipo          NUMBER CONSTRAINT nn_veh_tipo NOT NULL,
    id_combustible   NUMBER CONSTRAINT nn_veh_comb NOT NULL,
    id_propietario   NUMBER CONSTRAINT nn_veh_prop NOT NULL,
    CONSTRAINT pk_vehiculo PRIMARY KEY (id_vehiculo),
    CONSTRAINT uq_veh_placa UNIQUE (placa),
    -- Rango base estático; el límite exacto con SYSDATE se valida en el trigger trg_validar_anio_vehiculo
    CONSTRAINT chk_veh_anio CHECK (año_fabricacion BETWEEN 1900 AND 2030),
    CONSTRAINT fk_veh_ciudad FOREIGN KEY (id_ciudad) REFERENCES ciudad (id_ciudad),
    CONSTRAINT fk_veh_tipo FOREIGN KEY (id_tipo) REFERENCES tipo_vehiculo (id_tipo),
    CONSTRAINT fk_veh_combustible FOREIGN KEY (id_combustible) REFERENCES combustible (id_combustible),
    CONSTRAINT fk_veh_propietario FOREIGN KEY (id_propietario) REFERENCES propietario (id_propietario)
);




CREATE TABLE medicion_co2 (
    id_medicion  NUMBER,
    id_vehiculo  NUMBER CONSTRAINT nn_med_vehiculo NOT NULL,
    fecha        DATE CONSTRAINT nn_med_fecha NOT NULL,
    co2_g_km     NUMBER(8,2),
    temperatura  NUMBER(5,2),
    humedad      NUMBER(5,2),
    kilometraje  NUMBER,
    CONSTRAINT pk_medicion_co2 PRIMARY KEY (id_medicion),
    CONSTRAINT chk_med_co2 CHECK (co2_g_km BETWEEN 0 AND 1000),
    CONSTRAINT chk_med_humedad CHECK (humedad BETWEEN 0 AND 100),
    CONSTRAINT fk_med_vehiculo FOREIGN KEY (id_vehiculo) REFERENCES vehiculo (id_vehiculo)
)
PARTITION BY RANGE (fecha)
INTERVAL (NUMTOYMINTERVAL(3, 'MONTH'))
(
    PARTITION p_mediciones_base VALUES LESS THAN (DATE '2025-01-01')
);

CREATE TABLE mantenimiento (
    id_mantenimiento    NUMBER,
    id_vehiculo         NUMBER CONSTRAINT nn_mant_vehiculo NOT NULL,
    fecha               DATE CONSTRAINT nn_mant_fecha NOT NULL,
    tipo_mantenimiento  VARCHAR2(50),
    costo               NUMBER,
    taller              VARCHAR2(100),
    observaciones       VARCHAR2(500),
    CONSTRAINT pk_mantenimiento PRIMARY KEY (id_mantenimiento),
    CONSTRAINT fk_mant_vehiculo FOREIGN KEY (id_vehiculo) REFERENCES vehiculo (id_vehiculo)
);

CREATE TABLE normativa (
    id_normativa       NUMBER,
    id_tipo            NUMBER CONSTRAINT nn_norm_tipo NOT NULL,
    año_desde          NUMBER,
    año_hasta          NUMBER,
    co2_max_permitido  NUMBER,
    CONSTRAINT pk_normativa PRIMARY KEY (id_normativa),
    CONSTRAINT chk_norm_co2 CHECK (co2_max_permitido > 0),
    CONSTRAINT chk_norm_anios CHECK (año_desde <= año_hasta),
    CONSTRAINT fk_norm_tipo FOREIGN KEY (id_tipo) REFERENCES tipo_vehiculo (id_tipo)
);






CREATE TABLE medicion_baja (
    id_medicion  NUMBER PRIMARY KEY,
    id_vehiculo  NUMBER NOT NULL,
    fecha        DATE NOT NULL,
    co2_g_km     NUMBER(8,2),
    temperatura  NUMBER(5,2),
    humedad      NUMBER(5,2),
    kilometraje  NUMBER
);

CREATE TABLE medicion_media (
    id_medicion  NUMBER PRIMARY KEY,
    id_vehiculo  NUMBER NOT NULL,
    fecha        DATE NOT NULL,
    co2_g_km     NUMBER(8,2),
    temperatura  NUMBER(5,2),
    humedad      NUMBER(5,2),
    kilometraje  NUMBER
);

CREATE TABLE medicion_alta (
    id_medicion  NUMBER PRIMARY KEY,
    id_vehiculo  NUMBER NOT NULL,
    fecha        DATE NOT NULL,
    co2_g_km     NUMBER(8,2),
    temperatura  NUMBER(5,2),
    humedad      NUMBER(5,2),
    kilometraje  NUMBER
);






CREATE OR REPLACE TRIGGER trg_validar_anio_vehiculo
BEFORE INSERT OR UPDATE OF año_fabricacion ON vehiculo
FOR EACH ROW
BEGIN
    IF :NEW.año_fabricacion > EXTRACT(YEAR FROM SYSDATE) THEN
        RAISE_APPLICATION_ERROR(-20001, 'El año de fabricación no puede ser mayor al año actual.');
    END IF;
END;
/




-- ----------------------------------------------------------------------------
-- ÍNDICES ESTRATÉGICOS OBLIGATORIOS (CON JUSTIFICACIÓN)
-- ----------------------------------------------------------------------------

-- Justificación: Acelera los JOIN y agrupaciones entre VEHICULO y CIUDAD (ej. promedio de CO2 por ciudad).
CREATE INDEX idx_vehiculo_ciudad ON vehiculo(id_ciudad);

-- Justificación: Optimiza el cruce entre VEHICULO, TIPO_VEHICULO y NORMATIVA para detectar vehículos fuera de norma.
CREATE INDEX idx_vehiculo_tipo ON vehiculo(id_tipo);

-- Justificación: Evita Full Table Scan en MEDICION_CO2 al filtrar el historial de emisiones de un vehículo específico.
CREATE INDEX idx_medicion_vehiculo ON medicion_co2(id_vehiculo);

-- Justificación: Optimiza filtros temporales globales (ej. mediciones de los últimos 3 meses o del último año).
CREATE INDEX idx_medicion_fecha ON medicion_co2(fecha);

-- Justificación: Índice compuesto crítico para series temporales por vehículo (LAG, promedios móviles y última medición).
CREATE INDEX idx_medicion_vehiculo_fecha ON medicion_co2(id_vehiculo, fecha);

-- Justificación: Índice compuesto que acelera la comparación de emisiones 30 días antes y después de cada mantenimiento.
CREATE INDEX idx_mantenimiento_vehiculo_fecha ON mantenimiento(id_vehiculo, fecha);

-- ----------------------------------------------------------------------------
-- SECUENCIAS OBLIGATORIAS PARA CLAVES PRIMARIAS
-- ----------------------------------------------------------------------------

CREATE SEQUENCE seq_ciudad START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_tipo START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_combustible START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_propietario START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_vehiculo START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_medicion START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_mantenimiento START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_normativa START WITH 1 INCREMENT BY 1 NOCACHE;

-- ----------------------------------------------------------------------------
-- COMENTARIOS EN TABLAS Y COLUMNAS CLAVE (DICCIONARIO DE DATOS)
-- ----------------------------------------------------------------------------

COMMENT ON TABLE ciudad IS 'Catálogo de municipios y ciudades donde se encuentran matriculados los vehículos.';
COMMENT ON TABLE tipo_vehiculo IS 'Clasificación del parque automotor según categoría y factor base de emisión.';
COMMENT ON TABLE combustible IS 'Tipos de energía o combustible utilizados y su factor teórico de CO2.';
COMMENT ON TABLE propietario IS 'Personas naturales o jurídicas responsables de los vehículos.';
COMMENT ON TABLE vehiculo IS 'Registro maestro de vehículos monitoreados en el sistema.';
COMMENT ON TABLE medicion_co2 IS 'Registro histórico particionado de mediciones diarias de emisiones de CO2.';
COMMENT ON TABLE mantenimiento IS 'Historial de intervenciones mecánicas realizadas a cada vehículo.';
COMMENT ON TABLE normativa IS 'Límites máximos permitidos de CO2 según tipo de vehículo y año de fabricación.';

COMMENT ON COLUMN vehiculo.placa IS 'Identificador único vehicular (matrícula).';
COMMENT ON COLUMN vehiculo.año_fabricacion IS 'Año modelo del vehículo; determina la normativa ambiental aplicable.';
COMMENT ON COLUMN medicion_co2.co2_g_km IS 'Emisión medida en gramos de CO2 por kilómetro recorrido (rango 0 a 1000).';
COMMENT ON COLUMN normativa.co2_max_permitido IS 'Umbral máximo legal de emisiones en g/km para el rango de años definido.';
-- ============================================================================
-- ARCHIVO: 03_consultas.sql
-- DESCRIPCIÓN: 5 Consultas Básicas (Sección 2.2) + 4 Consultas Analíticas
--              Complejas (Sección 2.3) para el Sistema de Monitoreo CO2.
-- MOTOR: Oracle Database 19c o superior
-- ============================================================================

-- ============================================================================
-- PARTE 1: CONSULTAS BÁSICAS (5 CONSULTAS - 10 PUNTOS)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Listar todos los vehículos con su ciudad y tipo de vehículo.
-- ----------------------------------------------------------------------------
SELECT
    v.id_vehiculo,
    v.placa,
    v.modelo,
    v.año_fabricacion,
    v.cilindraje,
    c.nombre        AS ciudad,
    c.departamento,
    tv.nombre       AS tipo_vehiculo
FROM vehiculo v
JOIN ciudad c
    ON v.id_ciudad = c.id_ciudad
JOIN tipo_vehiculo tv
    ON v.id_tipo = tv.id_tipo
ORDER BY v.id_vehiculo;

-- ----------------------------------------------------------------------------
-- 2. Promedio de CO2 por ciudad.
-- ----------------------------------------------------------------------------
SELECT
    c.id_ciudad,
    c.nombre                          AS ciudad,
    c.departamento,
    COUNT(m.id_medicion)              AS total_mediciones,
    ROUND(AVG(m.co2_g_km), 2)         AS promedio_co2_g_km
FROM ciudad c
LEFT JOIN vehiculo v
    ON c.id_ciudad = v.id_ciudad
LEFT JOIN medicion_co2 m
    ON v.id_vehiculo = m.id_vehiculo
GROUP BY
    c.id_ciudad,
    c.nombre,
    c.departamento
ORDER BY promedio_co2_g_km DESC NULLS LAST;

-- ----------------------------------------------------------------------------
-- 3. Vehículos que superan la normativa vigente (usar tabla NORMATIVA).
-- ----------------------------------------------------------------------------
-- Nota: Cruza el tipo y año de fabricación del vehículo contra el rango legal,
-- identificando vehículos cuyo promedio o al menos una medición supera el tope.
SELECT
    v.id_vehiculo,
    v.placa,
    v.modelo,
    v.año_fabricacion,
    tv.nombre                           AS tipo_vehiculo,
    n.co2_max_permitido                 AS limite_normativa_g_km,
    ROUND(AVG(m.co2_g_km), 2)           AS promedio_co2_vehiculo,
    MAX(m.co2_g_km)                     AS pico_maximo_co2
FROM vehiculo v
JOIN tipo_vehiculo tv
    ON v.id_tipo = tv.id_tipo
JOIN normativa n
    ON v.id_tipo = n.id_tipo
   AND v.año_fabricacion BETWEEN n.año_desde AND n.año_hasta
JOIN medicion_co2 m
    ON v.id_vehiculo = m.id_vehiculo
GROUP BY
    v.id_vehiculo,
    v.placa,
    v.modelo,
    v.año_fabricacion,
    tv.nombre,
    n.co2_max_permitido
HAVING MAX(m.co2_g_km) > n.co2_max_permitido
ORDER BY pico_maximo_co2 DESC;

-- ----------------------------------------------------------------------------
-- 4. Total de mantenimientos y gasto total por vehículo (ordenado de mayor a menor gasto).
-- ----------------------------------------------------------------------------
SELECT
    v.id_vehiculo,
    v.placa,
    v.modelo,
    COUNT(mt.id_mantenimiento)        AS total_mantenimientos,
    NVL(SUM(mt.costo), 0)             AS gasto_total_cop
FROM vehiculo v
LEFT JOIN mantenimiento mt
    ON v.id_vehiculo = mt.id_vehiculo
GROUP BY
    v.id_vehiculo,
    v.placa,
    v.modelo
ORDER BY gasto_total_cop DESC;

-- ----------------------------------------------------------------------------
-- 5. Última medición registrada por vehículo (fecha más reciente).
-- ----------------------------------------------------------------------------
SELECT
    v.id_vehiculo,
    v.placa,
    v.modelo,
    m.id_medicion,
    m.fecha         AS fecha_ultima_medicion,
    m.co2_g_km      AS ultimo_co2_g_km,
    m.kilometraje
FROM vehiculo v
JOIN medicion_co2 m
    ON v.id_vehiculo = m.id_vehiculo
WHERE m.fecha = (
    SELECT MAX(m2.fecha)
    FROM medicion_co2 m2
    WHERE m2.id_vehiculo = v.id_vehiculo
)
ORDER BY v.id_vehiculo;


-- ============================================================================
-- PARTE 2: CONSULTAS ANALÍTICAS COMPLEJAS (4 CONSULTAS - 20 PUNTOS)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Ranking de vehículos más contaminantes:
--    Top 5 vehículos con mayor promedio de CO2 en los últimos 3 meses.
--    Incluye placa, tipo de vehículo, promedio CO2 y ranking (usar RANK()).
-- ----------------------------------------------------------------------------
WITH promedios_trimestre AS (
    SELECT
        v.placa,
        tv.nombre                   AS tipo_vehiculo,
        ROUND(AVG(m.co2_g_km), 2)   AS promedio_co2,
        RANK() OVER (
            ORDER BY AVG(m.co2_g_km) DESC
        )                           AS ranking
    FROM vehiculo v
    JOIN tipo_vehiculo tv
        ON v.id_tipo = tv.id_tipo
    JOIN medicion_co2 m
        ON v.id_vehiculo = m.id_vehiculo
    WHERE m.fecha >= ADD_MONTHS(TRUNC(SYSDATE), -3)
    GROUP BY
        v.id_vehiculo,
        v.placa,
        tv.nombre
)
SELECT
    ranking,
    placa,
    tipo_vehiculo,
    promedio_co2
FROM promedios_trimestre
WHERE ranking <= 5
ORDER BY ranking, placa;

-- ----------------------------------------------------------------------------
-- 2. Evolución mensual por vehículo:
--    Para cada vehículo y cada mes del último año: promedio CO2, diferencia
--    con el mes anterior (usar LAG) y promedio móvil de 3 meses.
-- ----------------------------------------------------------------------------
WITH serie_mensual AS (
    SELECT
        v.id_vehiculo,
        v.placa,
        TRUNC(m.fecha, 'MM')        AS mes,
        ROUND(AVG(m.co2_g_km), 2)   AS promedio_co2_mes
    FROM vehiculo v
    JOIN medicion_co2 m
        ON v.id_vehiculo = m.id_vehiculo
    WHERE m.fecha >= ADD_MONTHS(TRUNC(SYSDATE, 'MM'), -12)
    GROUP BY
        v.id_vehiculo,
        v.placa,
        TRUNC(m.fecha, 'MM')
)
SELECT
    placa,
    TO_CHAR(mes, 'YYYY-MM')                                 AS periodo_mes,
    promedio_co2_mes,
    ROUND(
        promedio_co2_mes - LAG(promedio_co2_mes) OVER (
            PARTITION BY id_vehiculo
            ORDER BY mes
        ), 2
    )                                                       AS diferencia_mes_anterior,
    ROUND(
        AVG(promedio_co2_mes) OVER (
            PARTITION BY id_vehiculo
            ORDER BY mes
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2
    )                                                       AS promedio_movil_3_meses
FROM serie_mensual
ORDER BY placa, mes;

-- ----------------------------------------------------------------------------
-- 3. Vehículos con mejora post-mantenimiento:
--    Compara emisiones promedio 30 días antes y 30 días después de cada
--    mantenimiento. Muestra solo aquellos con reducción > 10%, ordenados
--    por mayor mejora. (Usa CTE).
-- ----------------------------------------------------------------------------
WITH impacto_mantenimiento AS (
    SELECT
        mt.id_mantenimiento,
        v.placa,
        v.modelo,
        mt.fecha                AS fecha_mantenimiento,
        mt.tipo_mantenimiento,
        (
            SELECT AVG(m1.co2_g_km)
            FROM medicion_co2 m1
            WHERE m1.id_vehiculo = mt.id_vehiculo
              AND m1.fecha >= mt.fecha - 30
              AND m1.fecha <  mt.fecha
        )                       AS promedio_30d_antes,
        (
            SELECT AVG(m2.co2_g_km)
            FROM medicion_co2 m2
            WHERE m2.id_vehiculo = mt.id_vehiculo
              AND m2.fecha >  mt.fecha
              AND m2.fecha <= mt.fecha + 30
        )                       AS promedio_30d_despues
    FROM mantenimiento mt
    JOIN vehiculo v
        ON mt.id_vehiculo = v.id_vehiculo
)
SELECT
    id_mantenimiento,
    placa,
    modelo,
    fecha_mantenimiento,
    tipo_mantenimiento,
    ROUND(promedio_30d_antes, 2)    AS co2_antes_30d,
    ROUND(promedio_30d_despues, 2)  AS co2_despues_30d,
    ROUND(
        ((promedio_30d_antes - promedio_30d_despues) / promedio_30d_antes) * 100,
        2
    )                               AS porcentaje_reduccion
FROM impacto_mantenimiento
WHERE promedio_30d_antes > 0
  AND promedio_30d_despues IS NOT NULL
  AND ((promedio_30d_antes - promedio_30d_despues) / promedio_30d_antes) * 100 > 10
ORDER BY porcentaje_reduccion DESC;

-- ----------------------------------------------------------------------------
-- 4. Porcentaje de vehículos fuera de norma por ciudad:
--    Para cada ciudad, calcula el porcentaje de vehículos que han tenido
--    al menos una medición que supere el límite de la normativa vigente.
-- ----------------------------------------------------------------------------
WITH vehiculos_evaluados AS (
    SELECT
        c.id_ciudad,
        c.nombre        AS ciudad,
        v.id_vehiculo,
        MAX(
            CASE
                WHEN m.co2_g_km > n.co2_max_permitido THEN 1
                ELSE 0
            END
        )               AS tuvo_exceso
    FROM ciudad c
    LEFT JOIN vehiculo v
        ON c.id_ciudad = v.id_ciudad
    LEFT JOIN normativa n
        ON v.id_tipo = n.id_tipo
       AND v.año_fabricacion BETWEEN n.año_desde AND n.año_hasta
    LEFT JOIN medicion_co2 m
        ON v.id_vehiculo = m.id_vehiculo
    GROUP BY
        c.id_ciudad,
        c.nombre,
        v.id_vehiculo
)
SELECT
    ciudad,
    COUNT(id_vehiculo)                                          AS total_vehiculos_ciudad,
    SUM(tuvo_exceso)                                            AS vehiculos_fuera_norma,
    ROUND(
        CASE
            WHEN COUNT(id_vehiculo) = 0 THEN 0
            ELSE (SUM(tuvo_exceso) / COUNT(id_vehiculo)) * 100
        END,
        2
    )                                                           AS porcentaje_fuera_norma
FROM vehiculos_evaluados
GROUP BY
    id_ciudad,
    ciudad
ORDER BY porcentaje_fuera_norma DESC, ciudad;

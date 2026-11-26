-- Caso 1: Antes
EXPLAIN PLAN SET STATEMENT_ID = 'TUNING_1_ANTES' FOR
SELECT
    mt.id_mantenimiento,
    v.placa,
    v.modelo,
    mt.fecha AS fecha_mantenimiento,
    ROUND((
        SELECT AVG(m1.co2_g_km)
        FROM medicion_co2 m1
        WHERE m1.id_vehiculo = mt.id_vehiculo
          AND m1.fecha >= mt.fecha - 30
          AND m1.fecha <  mt.fecha
    ), 2) AS co2_antes_30d,
    ROUND((
        SELECT AVG(m2.co2_g_km)
        FROM medicion_co2 m2
        WHERE m2.id_vehiculo = mt.id_vehiculo
          AND m2.fecha >  mt.fecha
          AND m2.fecha <= mt.fecha + 30
    ), 2) AS co2_despues_30d
FROM mantenimiento mt
JOIN vehiculo v ON mt.id_vehiculo = v.id_vehiculo
WHERE (
    SELECT AVG(m2.co2_g_km)
    FROM medicion_co2 m2
    WHERE m2.id_vehiculo = mt.id_vehiculo
      AND m2.fecha >  mt.fecha
      AND m2.fecha <= mt.fecha + 30
) < (
    SELECT AVG(m1.co2_g_km)
    FROM medicion_co2 m1
    WHERE m1.id_vehiculo = mt.id_vehiculo
      AND m1.fecha >= mt.fecha - 30
      AND m1.fecha <  mt.fecha
) * 0.90;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'TUNING_1_ANTES', 'TYPICAL'));

-- Caso 1: Despues
EXPLAIN PLAN SET STATEMENT_ID = 'TUNING_1_DESPUES' FOR
WITH comparativa_unica AS (
    SELECT
        mt.id_mantenimiento,
        v.placa,
        v.modelo,
        mt.fecha AS fecha_mantenimiento,
        mt.tipo_mantenimiento,
        AVG(CASE WHEN m.fecha < mt.fecha THEN m.co2_g_km END) AS promedio_30d_antes,
        AVG(CASE WHEN m.fecha > mt.fecha THEN m.co2_g_km END) AS promedio_30d_despues
    FROM mantenimiento mt
    JOIN vehiculo v ON mt.id_vehiculo = v.id_vehiculo
    JOIN medicion_co2 m
        ON m.id_vehiculo = mt.id_vehiculo
       AND m.fecha BETWEEN mt.fecha - 30 AND mt.fecha + 30
       AND m.fecha <> mt.fecha
    GROUP BY mt.id_mantenimiento, v.placa, v.modelo, mt.fecha, mt.tipo_mantenimiento
)
SELECT
    id_mantenimiento,
    placa,
    modelo,
    fecha_mantenimiento,
    tipo_mantenimiento,
    ROUND(promedio_30d_antes, 2) AS co2_antes_30d,
    ROUND(promedio_30d_despues, 2) AS co2_despues_30d,
    ROUND(((promedio_30d_antes - promedio_30d_despues) / promedio_30d_antes) * 100, 2) AS porcentaje_reduccion
FROM comparativa_unica
WHERE promedio_30d_antes > 0
  AND promedio_30d_despues < promedio_30d_antes * 0.90
ORDER BY porcentaje_reduccion DESC;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'TUNING_1_DESPUES', 'TYPICAL'));

-- Caso 2: Antes
EXPLAIN PLAN SET STATEMENT_ID = 'TUNING_2_ANTES' FOR
SELECT *
FROM (
    SELECT
        v.placa,
        tv.nombre AS tipo_vehiculo,
        ROUND(AVG(m.co2_g_km), 2) AS promedio_co2,
        RANK() OVER (ORDER BY AVG(m.co2_g_km) DESC) AS ranking
    FROM medicion_co2 m
    JOIN vehiculo v ON m.id_vehiculo = v.id_vehiculo
    JOIN tipo_vehiculo tv ON v.id_tipo = tv.id_tipo
    WHERE TO_CHAR(m.fecha, 'YYYY-MM-DD') >= TO_CHAR(ADD_MONTHS(SYSDATE, -3), 'YYYY-MM-DD')
    GROUP BY v.placa, tv.nombre
)
WHERE ranking <= 5;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'TUNING_2_ANTES', 'TYPICAL'));

-- Caso 2: Despues
EXPLAIN PLAN SET STATEMENT_ID = 'TUNING_2_DESPUES' FOR
WITH top_mediciones AS (
    SELECT
        id_vehiculo,
        AVG(co2_g_km) AS promedio_raw,
        RANK() OVER (ORDER BY AVG(co2_g_km) DESC) AS ranking
    FROM medicion_co2
    WHERE fecha >= ADD_MONTHS(TRUNC(SYSDATE), -3)
    GROUP BY id_vehiculo
)
SELECT
    tm.ranking,
    v.placa,
    tv.nombre AS tipo_vehiculo,
    ROUND(tm.promedio_raw, 2) AS promedio_co2
FROM top_mediciones tm
JOIN vehiculo v ON tm.id_vehiculo = v.id_vehiculo
JOIN tipo_vehiculo tv ON v.id_tipo = tv.id_tipo
WHERE tm.ranking <= 5
ORDER BY tm.ranking, v.placa;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'TUNING_2_DESPUES', 'TYPICAL'));
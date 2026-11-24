-- ============================================================================
-- PROYECTO [OMEGA] — CONSULTAS DE VALIDACIÓN, OPTIMIZACIÓN Y SEGURIDAD QA
-- Archivo: 03_queries_optimizacion.sql
-- Motor: PostgreSQL 16 (Ejecutar bloque por bloque en Neon SQL Editor para
--        obtener capturas reales de evidencia para el Informe EV3)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PRUEBA 1 (ANEXO C): Últimos 3 precios históricos de compra y sus fechas
-- Debe retornar los 3 precios del Compresor Bitzer 4HP ordenados del más reciente
-- ----------------------------------------------------------------------------
SELECT
    a.codigo_sku,
    a.nombre,
    v.posicion_precio,
    v.costo_unitario_tasado,
    v.precio_lista_referencia,
    v.fecha_actualizacion
FROM vw_ultimos_3_precios_articulos v
JOIN articulos a ON a.id_articulo = v.id_articulo
ORDER BY a.codigo_sku, v.posicion_precio;

-- ----------------------------------------------------------------------------
-- PRUEBA 2 (RN-13): Verificar que la Nota de Crédito NC-0089 generó la REVERSA
-- automática en movimientos_cardex, rebajó stock (20 -> 18) y dejó bitácora
-- ----------------------------------------------------------------------------
SELECT id_movimiento, tipo_movimiento, cantidad, saldo_stock_resultante, costo_pmp_momento, observaciones
FROM movimientos_cardex
ORDER BY id_movimiento;

SELECT id_bitacora, entidad_afectada, accion, valor_nuevo_json, motivo, fecha_hora
FROM bitacora_auditoria
ORDER BY id_bitacora DESC;

-- ----------------------------------------------------------------------------
-- PRUEBA 3 (DASHBOARD KPI + EXPLAIN ANALYZE — Criterio 3.1.2.4 Optimización)
-- 3A: Semáforo presupuestario de obras activas
-- ----------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT
    o.codigo_obra,
    o.nombre_proyecto,
    c.razon_social AS cliente,
    o.tipo_servicio,
    o.estado_actual,
    o.presupuesto_asignado,
    o.costo_acumulado_real,
    ROUND((o.costo_acumulado_real / NULLIF(o.presupuesto_asignado, 0)) * 100, 1) AS pct_consumido,
    CASE
        WHEN o.costo_acumulado_real > o.presupuesto_asignado THEN 'ROJO_SOBREGIRO'
        WHEN o.costo_acumulado_real >= o.presupuesto_asignado * 0.80 THEN 'AMARILLO_ALERTA'
        ELSE 'VERDE_OK'
    END AS semaforo_presupuesto
FROM obras o
JOIN clientes c ON c.id_cliente = o.id_cliente
WHERE o.estado_actual = 'EN_PROCESO';

-- 3B: Alerta automática de stock crítico (bajo mínimo)
SELECT
    codigo_sku,
    nombre,
    stock_fisico,
    stock_minimo_critico,
    (stock_minimo_critico - stock_fisico) AS unidades_faltantes
FROM articulos
WHERE activo = TRUE AND stock_fisico <= stock_minimo_critico
ORDER BY unidades_faltantes DESC;

-- ----------------------------------------------------------------------------
-- PRUEBA 4 (HÍBRIDA SQL + JSONB con índice GIN — Criterio 3.1.2.3 / 3.1.2.4)
-- Filtra checklists móviles que reportaron "FALLA" en conexiones eléctricas
-- ----------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT
    o.codigo_obra,
    o.nombre_proyecto,
    u.nombre_completo AS tecnico,
    ch.tipo_equipo_frigorifico,
    ch.respuestas_botones_json->'lecturas_rapidas_botones'->>'conexiones_electricas' AS estado_electrico,
    ch.respuestas_botones_json->'telemetria_opcional'->>'temperatura_camara_c' AS temp_camara_c
FROM checklists ch
JOIN hojas_servicio hs ON hs.id_hoja_servicio = ch.id_hoja_servicio
JOIN obras o ON o.id_obra = hs.id_obra
JOIN usuarios u ON u.id_usuario = hs.id_tecnico
WHERE ch.respuestas_botones_json @> '{"lecturas_rapidas_botones": {"conexiones_electricas": "FALLA"}}'::jsonb;

-- ----------------------------------------------------------------------------
-- PRUEBA 5 (SEGURIDAD ANTIFRAUDE RN-01 — Ejecutar por separado en Neon)
-- RESULTADO ESPERADO: ERROR 42501 "VIOLACIÓN DE SEGURIDAD (RN-01): El borrado
-- físico (DELETE) está bloqueado en la tabla movimientos_cardex."
-- (Saca captura de ese error rojo: es evidencia directa del Criterio 3.1.5.10)
-- ----------------------------------------------------------------------------
-- DELETE FROM movimientos_cardex WHERE id_movimiento = 1;
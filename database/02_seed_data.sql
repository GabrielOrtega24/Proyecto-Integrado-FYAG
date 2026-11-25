-- ============================================================================
-- PROYECTO [OMEGA] — DATOS DE PRUEBA REALISTAS (SEED DATA FYAG)
-- Archivo: 02_seed_data.sql
-- Motor: PostgreSQL 16 (Neon Cloud / Local)
-- Propósito:
--   Poblar las 24 tablas respetando integridad referencial, validación de RUT
--   Módulo 11, los 6 perfiles RBAC, los 8 tipos de servicio, los 4 estados
--   oficiales de obra, historial de últimos 3 precios de compra y disparar en
--   vivo el Trigger automático de Nota de Crédito (RN-13).
-- ============================================================================

-- 1. ROLES (6 perfiles oficiales RBAC — RNF-05)
INSERT INTO roles (nombre_rol, descripcion, permisos_rbac_json, nivel_acceso) VALUES
('Administrador General', 'Acceso total al sistema, aprobación de reversas y auditoría.', '{"dashboard": true, "reversas_aprobar": true, "usuarios": true, "delete_fisico": false}'::jsonb, 10),
('Administrativo y Finanzas', 'Gestión de clientes, proveedores, facturas, presupuestos y cobranzas.', '{"clientes": true, "proveedores": true, "facturas": true, "pagos": true, "delete_fisico": false}'::jsonb, 8),
('Administrador de Bodega', 'Catálogo, ingresos, despachos a obra, inventarios y solicitud de reversas.', '{"bodega": true, "cardex": true, "reversas_solicitar": true, "delete_fisico": false}'::jsonb, 7),
('Supervisor de Obras', 'Gestión de obras, asignación de técnicos, estados y validación de cierre.', '{"obras": true, "hojas_validar": true, "despacho_solicitar": true, "delete_fisico": false}'::jsonb, 6),
('Tecnico de Terreno', 'Acceso exclusivo a PWA móvil (sin visibilidad de costos ni márgenes).', '{"pwa": true, "ver_costos": false, "ver_precios": false, "delete_fisico": false}'::jsonb, 4),
('Perfil Consulta', 'Acceso estrictamente de solo lectura para auditorías internas.', '{"solo_lectura": true, "exportar_pdf": true, "delete_fisico": false}'::jsonb, 2);

-- 2. USUARIOS (1 usuario por perfil RBAC — RUTs válidos Módulo 11)
INSERT INTO usuarios (id_rol, rut, email, nombre_completo, password_hash) VALUES
(1, '11111111-1', 'gerencia@fyag.cl',     'Carlos Mendoza (Admin General)',     'argon2id$v=19$m=65536,t=3,p=4$demo_hash_admin_01'),
(2, '12345678-5', 'finanzas@fyag.cl',     'Patricia Soto (Finanzas)',           'argon2id$v=19$m=65536,t=3,p=4$demo_hash_finanzas_02'),
(3, '13456789-9', 'bodega@fyag.cl',       'Camila Rojas (Admin Bodega)',        'argon2id$v=19$m=65536,t=3,p=4$demo_hash_bodega_03'),
(4, '14567890-0', 'supervisor@fyag.cl',   'Rodrigo Paredes (Supervisor Obras)', 'argon2id$v=19$m=65536,t=3,p=4$demo_hash_sup_04'),
(5, '15678901-1', 'jorge.munoz@fyag.cl',  'Jorge Muñoz (Técnico Terreno)',      'argon2id$v=19$m=65536,t=3,p=4$demo_hash_tec_05'),
(6, '16789012-1', 'auditoria@fyag.cl',    'Elena Fuentes (Perfil Consulta)',    'argon2id$v=19$m=65536,t=3,p=4$demo_hash_cons_06');

-- 3. CATEGORÍAS (8 categorías oficiales del Anexo C)
INSERT INTO categorias (nombre, codigo_prefijo, descripcion) VALUES
('Refrigeración',      'REF', 'Compresores, gases refrigerantes y componentes de cadena de frío'),
('Electricidad',       'ELE', 'Cables, contactores, tableros y protecciones eléctricas'),
('Aire acondicionado', 'AAC', 'Equipos split, ductos y climatización industrial'),
('Repuestos',          'REP', 'Filtros, válvulas, sellos y repuestos críticos'),
('Fitting',            'FIT', 'Codos de cobre, tuberías, coplas y soldadura'),
('Ferretería',         'FER', 'Pernos, fijaciones, soportes y abrasivos'),
('Herramientas',       'HER', 'Taladros, bombas de vacío y manómetros'),
('Otros',              'OTR', 'Insumos varios de operación en terreno');

-- 4. PROVEEDORES (con región, comuna, ciudad y datos bancarios — Anexo C)
INSERT INTO proveedores (rut, razon_social, giro, direccion, region, comuna, ciudad, telefono, banco, tipo_cuenta, numero_cuenta, email_pagos, plazo_credito_dias) VALUES
('76123456-0', 'Distribuidora FríoSur Industrial SpA', 'Importación y venta de equipos de refrigeración', 'Av. Alonso de Ercilla 2450', 'Biobío', 'Concepción', 'Concepción', '+56 41 255 1100', 'Banco de Chile', 'Cuenta Corriente', '00-123-45678-01', 'pagos@friosur.cl', 30),
('76987654-5', 'ElectroChile Suministros Ltda.',       'Comercialización de insumos eléctricos industriales', 'Panamericana Sur Km 402', 'Ñuble', 'Chillán', 'Chillán', '+56 42 222 8890', 'Banco Santander', 'Cuenta Corriente', '00-987-65432-09', 'tesoreria@electrochile.cl', 45);

-- 5. CLIENTES MANDANTES (con región/comuna/ciudad y Representante Legal — Anexo C)
INSERT INTO clientes (rut, razon_social, giro, direccion, region, comuna, ciudad, representante_legal_nombre, representante_legal_rut) VALUES
('77111222-6', 'Agrocomercial San Pedro SpA',      'Packing y exportación de fruta fresca', 'Camino a Pinto Km 12', 'Ñuble', 'Coihueco', 'Chillán', 'Roberto Alarcón Díaz', '10222333-0'),
('77333444-7', 'Frutícola Valle del Itata Ltda.',  'Procesamiento y almacenamiento frigorífico', 'Ruta N-50 Km 8', 'Ñuble', 'San Carlos', 'San Carlos', 'Marcela Valdés Vera', '10444555-1');

-- 6. CONTACTOS (Comerciales de Proveedores + Proyectos y Finanzas de Clientes)
INSERT INTO contactos (id_cliente, id_proveedor, tipo_contacto, nombre_contacto, rut_contacto, cargo, email, telefono, es_principal) VALUES
(NULL, 1, 'COMERCIAL', 'Andrés Morales', '18123456-3', 'Ejecutivo de Ventas', 'amorales@friosur.cl', '+56 9 8811 2233', TRUE),
(1, NULL, 'PROYECTOS', 'Felipe Lagos',   '19234567-7', 'Jefe de Mantención',  'flagos@sanpedro.cl',  '+56 9 7744 5566', TRUE),
(1, NULL, 'FINANZAS',  'Claudia Reyes',  '17345678-6', 'Encargada Finanzas',  'creyes@sanpedro.cl',  '+56 9 6633 4455', FALSE),
(2, NULL, 'PROYECTOS', 'Héctor Morales', '16456789-3', 'Jefe de Planta',      'hmorales@itata.cl',   '+56 9 5522 3344', TRUE);

-- 7. ARTÍCULOS (Catálogo inicial — incluye artículos en stock crítico para probar alertas)
INSERT INTO articulos (id_categoria, codigo_sku, codigo_barras, nombre, unidad_medida, sector_bodega, ubicacion_bodega, stock_fisico, stock_comprometido, stock_minimo_critico, ultimo_costo_compra, costo_promedio_pmp, precio_lista, fecha_ultima_actualizacion_precio) VALUES
(1, 'COMP-BITZER-4HP', '7801234500001', 'Compresor Bitzer 4HP Semi-Hermético', 'UN',  'BODEGA_CENTRAL', 'Rack A-01',   10.00, 1.00,  3.00, 500000.00, 500000.00, 680000.00, NOW() - INTERVAL '30 days'),
(1, 'REF-001',         '7801234500012', 'Gas Refrigerante R410A (Cilindro)',   'CIL', 'BODEGA_CENTRAL', 'Estante A-02', 3.00, 0.00,  8.00,  85000.00,  85000.00, 125000.00, NOW() - INTERVAL '15 days'),
(2, 'ELE-024',         '7801234500241', 'Cable EVA 2,5 mm² Libre Halógeno',    'MT',  'BODEGA_CENTRAL', 'Estante B-03',120.00, 0.00, 50.00,    950.00,    950.00,   1500.00, NOW() - INTERVAL '10 days'),
(4, 'REP-031',         '7801234500319', 'Filtro Deshidratador 1/4 Soldable',   'UN',  'BODEGA_CENTRAL', 'Cajón C-08',   2.00, 0.00,  6.00,  18000.00,  18000.00,  28000.00, NOW() - INTERVAL '20 days'),
(4, 'VAL-DANFOSS-01',  '7801234500410', 'Válvula Expansión Termostática Danfoss','UN','BODEGA_CENTRAL', 'Cajón C-09',  20.00, 2.00,  5.00,  40000.00,  40000.00,  55000.00, NOW() - INTERVAL '12 days');

-- 8. PRESUPUESTOS
INSERT INTO presupuestos (id_cliente, id_usuario_emisor, codigo_presupuesto, fecha_emision, monto_estimado_neto, margen_esperado_pct, estado) VALUES
(1, 2, 'PRES-2026-038', CURRENT_DATE - 10, 4500000.00, 28.50, 'APROBADO'),
(2, 2, 'PRES-2026-039', CURRENT_DATE - 5,  2100000.00, 32.00, 'APROBADO');

-- 9. OBRAS (Usando los 8 tipos de servicio y 4 estados oficiales del Anexo C)
INSERT INTO obras (id_cliente, id_presupuesto, id_supervisor, id_tecnico_responsable, codigo_obra, nombre_proyecto, ubicacion_planta, tipo_servicio, estado_actual, presupuesto_asignado, costo_acumulado_real, horas_hombre_totales) VALUES
(1, 1, 4, 5, 'OB-2026-038', 'Cámara Frigorífica Planta Norte',   'Camino a Pinto Km 12, Coihueco', 'PROYECTO',      'EN_PROCESO', 4500000.00, 1250000.00, 14.50),
(2, 2, 4, 5, 'OB-2026-039', 'Mantención Túnel de Prefío #2',     'Ruta N-50 Km 8, San Carlos',     'MANTENCION',    'EN_PROCESO', 2100000.00,  420000.00,  8.00),
(1, NULL, 4, 5, 'OB-2026-032', 'Emergencia Tablero Eléctrico',   'Camino a Pinto Km 12, Coihueco', 'EMERGENCIA',    'FINALIZADA',  850000.00,  590000.00,  6.00);

INSERT INTO historial_estados_obra (id_obra, id_usuario, estado_anterior, estado_nuevo, justificacion_cambio) VALUES
(1, 4, NULL,         'EN_PROCESO', 'Apertura oficial de obra con presupuesto PRES-2026-038 aprobado.'),
(3, 4, 'EN_PROCESO', 'FINALIZADA', 'Cierre validado con hoja firmada, costos imputados y horas-hombre completas.');

-- 10. DOCUMENTOS DE COMPRA (2 Facturas históricas + 1 Factura reciente para probar 3 precios históricos)
-- Factura 1 (hace 40 días)
INSERT INTO documentos_compra (id_proveedor, id_usuario_creador, tipo_doc, folio_documento, fecha_emision, fecha_vencimiento, subtotal_neto, descuento_general_pct, desc_pronto_pago_pct, monto_neto_final, monto_iva_total, monto_total, estado_documento, estado_pago) VALUES
(1, 3, 'FACTURA', 'FC-4100', CURRENT_DATE - 40, CURRENT_DATE - 10, 1000000.00, 2.00, 0.00,  980000.00, 186200.00, 1166200.00, 'CONFIRMADO', 'PAGADO');

INSERT INTO lineas_compra (id_documento_compra, id_articulo, cantidad, precio_unitario_lista, desc_1_pct, desc_2_pct, desc_3_pct, costo_unitario_tasado, subtotal_linea) VALUES
(1, 1, 2.00, 520000.00, 5.00, 0.00, 0.00, 494000.00, 988000.00);

-- Factura 2 (hace 20 días)
INSERT INTO documentos_compra (id_proveedor, id_usuario_creador, tipo_doc, folio_documento, fecha_emision, fecha_vencimiento, subtotal_neto, descuento_general_pct, desc_pronto_pago_pct, monto_neto_final, monto_iva_total, monto_total, estado_documento, estado_pago) VALUES
(1, 3, 'FACTURA', 'FC-4250', CURRENT_DATE - 20, CURRENT_DATE + 10, 1500000.00, 0.00, 2.00, 1470000.00, 279300.00, 1749300.00, 'CONFIRMADO', 'PENDIENTE');

INSERT INTO lineas_compra (id_documento_compra, id_articulo, cantidad, precio_unitario_lista, desc_1_pct, desc_2_pct, desc_3_pct, costo_unitario_tasado, subtotal_linea) VALUES
(2, 1, 3.00, 550000.00, 8.00, 2.00, 0.00, 495880.00, 1487640.00);

-- Factura 3 (hoy — 3 descuentos en cascada 10% + 5% + 2% + pronto pago 3% = $487.657,80)
INSERT INTO documentos_compra (id_proveedor, id_usuario_creador, tipo_doc, folio_documento, fecha_emision, fecha_vencimiento, subtotal_neto, descuento_general_pct, desc_pronto_pago_pct, monto_neto_final, monto_iva_total, monto_total, estado_documento, estado_pago) VALUES
(1, 3, 'FACTURA', 'FC-4410', CURRENT_DATE, CURRENT_DATE + 30, 5027400.00, 0.00, 3.00, 4876578.00, 926549.82, 5803127.82, 'CONFIRMADO', 'PENDIENTE');

INSERT INTO lineas_compra (id_documento_compra, id_articulo, cantidad, precio_unitario_lista, desc_1_pct, desc_2_pct, desc_3_pct, costo_unitario_tasado, subtotal_linea) VALUES
(3, 1, 10.00, 600000.00, 10.00, 5.00, 2.00, 487657.80, 4876578.00);

-- 11. MOVIMIENTOS DE CARDEX Y EGRESO A OBRA (Valorización Dual: PMP vs. Precio Lista)
INSERT INTO movimientos_cardex (id_articulo, id_usuario, id_documento_compra, id_obra, tipo_movimiento, cantidad, saldo_stock_resultante, costo_pmp_momento, precio_lista_momento, observaciones) VALUES
(1, 3, 3, NULL, 'INGRESO',      10.00, 20.00, 493828.90, 680000.00, 'Ingreso Factura FC-4410 con 3 descuentos en cascada'),
(5, 3, NULL, 1, 'EGRESO_OBRA',  -4.00, 16.00,  40000.00,  55000.00, 'Despacho de 4 válvulas Danfoss a OB-2026-038');

UPDATE articulos SET stock_fisico = 20.00, costo_promedio_pmp = 493828.90 WHERE id_articulo = 1;
UPDATE articulos SET stock_fisico = 16.00 WHERE id_articulo = 5;

INSERT INTO egresos_obra (id_obra, id_movimiento, id_articulo, cantidad_despachada, costo_imputado_pmp, valor_imputado_lista, receptor_nombre) VALUES
(1, 2, 5, 4.00, 160000.00, 220000.00, 'Jorge Muñoz');

-- 12. PRUEBA AUTOMÁTICA DE NOTA DE CRÉDITO (RN-13):
-- Se crea en BORRADOR, se carga la línea devuelta (2 compresores) y al pasar a CONFIRMADO
-- el Trigger trg_aplicar_nota_credito genera automáticamente la REVERSA en Cardex,
-- rebaja stock_fisico de 20 -> 18, recalcula PMP y registra en bitacora_auditoria.
INSERT INTO documentos_compra (id_proveedor, id_usuario_creador, id_documento_referencia, tipo_doc, folio_documento, fecha_emision, subtotal_neto, monto_neto_final, monto_iva_total, monto_total, estado_documento, estado_pago, observaciones) VALUES
(1, 3, 3, 'NOTA_CREDITO', 'NC-0089', CURRENT_DATE, 975315.60, 975315.60, 185309.96, 1160625.56, 'BORRADOR', 'ANULADO', 'Devolución de 2 compresores Bitzer 4HP por daño en embalaje');

INSERT INTO lineas_compra (id_documento_compra, id_articulo, cantidad, precio_unitario_lista, costo_unitario_tasado, subtotal_linea) VALUES
(4, 1, 2.00, 600000.00, 487657.80, 975315.60);

-- Al ejecutar este UPDATE se dispara automáticamente el Trigger RN-13:
UPDATE documentos_compra
SET estado_documento = 'CONFIRMADO'
WHERE folio_documento = 'NC-0089';

-- 13. PAGOS (1 pago a proveedor + 1 cobro a cliente)
INSERT INTO pagos (id_documento_compra, id_obra, id_usuario_registro, tipo_flujo, monto_pagado, medio_pago, comprobante_ref) VALUES
(1, NULL, 2, 'PAGO_PROVEEDOR', 1166200.00, 'Transferencia Bancaria', 'TRF-BCI-88421'),
(NULL, 3, 2, 'COBRO_CLIENTE',   850000.00, 'Transferencia Bancaria', 'DEP-SANPEDRO-032');

-- 14. INVENTARIO FÍSICO Y DETALLE
INSERT INTO inventarios_fisicos (id_usuario_bodega, fecha_cierre, estado, observaciones_auditoria) VALUES
(3, NOW(), 'FINALIZADO', 'Cuadratura mensual de bodega central Chillán');

INSERT INTO detalles_inventario (id_inventario, id_articulo, stock_sistema_esperado, stock_fisico_contado, diferencia_merma, ajuste_aplicado) VALUES
(1, 2,   3.00,   3.00,  0.00, FALSE),
(1, 3, 120.00, 122.00,  2.00, FALSE);

-- 15. TERRENO PWA: HOJA DE SERVICIO OFFLINE, CONSUMO, EVIDENCIA SHA-256 Y CHECKLIST JSONB
INSERT INTO hojas_servicio (id_obra, id_tecnico, uuid_offline_pwa, fecha_inicio, fecha_termino, horas_hombre_registradas, gps_latitud, gps_longitud, sincronizado_offline, observaciones) VALUES
(1, 5, 'c4f1a820-91b2-4e11-8a55-001928374655', NOW() - INTERVAL '3 hours', NOW() - INTERVAL '1 hour', 2.00, -36.606600, -72.103400, TRUE, 'Sincronizada automáticamente al salir de cámara frigorífica sin señal 4G.');

INSERT INTO consumos_material (id_hoja_servicio, id_articulo, cantidad_utilizada, alerta_discrepancia_stock) VALUES
(1, 2, 1.00, FALSE);

INSERT INTO evidencias (id_evidencia, id_hoja_servicio, tipo_evidencia, s3_object_key_uri, hash_sha256_integridad, peso_kb, firmante_nombre, firmante_rut) VALUES
(DEFAULT, 1, 'FOTO_WEBP', 's3://fyag-evidencias/obras/2026/OB-2026-038/compresor_01.webp', 'a3f5c8d9e1b204769182736455aabbccddeeff00112233445566778899aabbcc', 238, NULL, NULL),
(DEFAULT, 1, 'FIRMA_PNG', 's3://fyag-evidencias/obras/2026/OB-2026-038/firma_cliente.png',  '9f8e7d6c5b4a3210fedcba98765432100123456789abcdef0123456789abcdef',  42, 'Felipe Lagos', '19234567-7');

INSERT INTO checklists (id_hoja_servicio, tipo_equipo_frigorifico, respuestas_botones_json, aprobado_operativo) VALUES
(1, 'COMPRESOR_TORNILLO_MYCOM_NH3', '{
    "esquema_version": "v2.1",
    "lecturas_rapidas_botones": {
        "equipo_limpio": "SI",
        "temperatura_en_rango": "NO",
        "conexiones_electricas": "FALLA",
        "drenaje_y_sellos": "SI"
    },
    "telemetria_opcional": {
        "temperatura_camara_c": -18.4,
        "humedad_relativa_pct": 85
    }
}'::jsonb, FALSE);
-- ============================================================================
-- PROYECTO [OMEGA] — PLATAFORMA INTEGRADA LOMT (ERP WEB + PWA MÓVIL)
-- Cliente: Frío y Agroindustria SpA (FYAG) — Chillán, Región de Ñuble
-- Motor: PostgreSQL 16 (100% compatible con Neon, Supabase y Render Cloud)
-- Archivo: 01_schema_ddl.sql
-- Autor: Vicente Cacerez (Especialista en Base de Datos, Seguridad y QA)
-- Descripción:
--   Esquema relacional completo en Tercera Forma Normal (3FN) con soporte
--   híbrido JSONB (índices GIN), integridad referencial estricta
--   (ON DELETE RESTRICT), validación de RUT chileno Módulo 11, política
--   antifraude de Cero Borrado Físico (RN-01), historial de últimos 3 precios
--   de compra, reversión automática de Notas de Crédito (RN-13) y catálogo
--   oficial de 8 tipos de servicio y 4 estados de obra (Anexo C).
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 0. FUNCIÓN UTILITARIA: VALIDACIÓN DE RUT CHILENO (ALGORITMO MÓDULO 11)
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_validar_rut_chileno(p_rut TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_limpio TEXT;
    v_cuerpo TEXT;
    v_dv_ingresado CHAR(1);
    v_dv_calculado CHAR(1);
    v_suma INTEGER := 0;
    v_multiplo INTEGER := 2;
    v_resto INTEGER;
    v_i INTEGER;
BEGIN
    IF p_rut IS NULL THEN
        RETURN FALSE;
    END IF;

    v_limpio := UPPER(REGEXP_REPLACE(p_rut, '[^0-9Kk]', '', 'g'));
    IF LENGTH(v_limpio) < 8 OR LENGTH(v_limpio) > 9 THEN
        RETURN FALSE;
    END IF;

    v_cuerpo := SUBSTRING(v_limpio FROM 1 FOR LENGTH(v_limpio) - 1);
    v_dv_ingresado := SUBSTRING(v_limpio FROM LENGTH(v_limpio) FOR 1);

    FOR v_i IN REVERSE LENGTH(v_cuerpo)..1 LOOP
        v_suma := v_suma + (CAST(SUBSTRING(v_cuerpo FROM v_i FOR 1) AS INTEGER) * v_multiplo);
        v_multiplo := CASE WHEN v_multiplo = 7 THEN 2 ELSE v_multiplo + 1 END;
    END LOOP;

    v_resto := 11 - (v_suma % 11);
    v_dv_calculado := CASE
        WHEN v_resto = 11 THEN '0'
        WHEN v_resto = 10 THEN 'K'
        ELSE CAST(v_resto AS CHAR(1))
    END;

    RETURN v_dv_ingresado = v_dv_calculado;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- DOMINIO 1: SEGURIDAD, AUTENTICACIÓN RBAC Y AUDITORÍA INMUTABLE
-- ============================================================================

-- 1. roles (6 perfiles oficiales RBAC — RNF-05)
CREATE TABLE roles (
    id_rol              SERIAL PRIMARY KEY,
    nombre_rol          VARCHAR(50) NOT NULL UNIQUE,
    descripcion         VARCHAR(200),
    permisos_rbac_json  JSONB NOT NULL DEFAULT '{}'::jsonb,
    nivel_acceso        SMALLINT NOT NULL CHECK (nivel_acceso BETWEEN 1 AND 10),
    activo              BOOLEAN NOT NULL DEFAULT TRUE
);

-- 2. usuarios (Autenticación Stateless JWT + Bloqueo Fuerza Bruta + Soft Delete)
CREATE TABLE usuarios (
    id_usuario          SERIAL PRIMARY KEY,
    id_rol              INTEGER NOT NULL REFERENCES roles(id_rol)
                            ON DELETE RESTRICT ON UPDATE CASCADE,
    rut                 VARCHAR(12) NOT NULL UNIQUE
                            CHECK (fn_validar_rut_chileno(rut)),
    email               VARCHAR(120) NOT NULL UNIQUE,
    nombre_completo     VARCHAR(150) NOT NULL,
    password_hash       VARCHAR(255) NOT NULL,
    intentos_fallidos   SMALLINT NOT NULL DEFAULT 0 CHECK (intentos_fallidos >= 0),
    bloqueado_hasta     TIMESTAMPTZ,
    ultimo_acceso       TIMESTAMPTZ,
    activo              BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. bitacora_auditoria (Tabla INSERT-ONLY con snapshots JSONB — RN-06, RNF-04)
CREATE TABLE bitacora_auditoria (
    id_bitacora         BIGSERIAL PRIMARY KEY,
    id_usuario          INTEGER REFERENCES usuarios(id_usuario)
                            ON DELETE RESTRICT ON UPDATE CASCADE,
    fecha_hora          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    entidad_afectada    VARCHAR(60) NOT NULL,
    id_registro_afectado VARCHAR(60) NOT NULL,
    accion              VARCHAR(30) NOT NULL,
    valor_anterior_json JSONB,
    valor_nuevo_json    JSONB NOT NULL DEFAULT '{}'::jsonb,
    motivo              TEXT NOT NULL,
    ip_origen           INET
);

-- ============================================================================
-- DOMINIO 2: MAESTROS COMERCIALES, CATÁLOGO Y ABASTECIMIENTO
-- ============================================================================

-- 4. proveedores (Incluye ubicación geográfica obligatoria y datos bancarios — Anexo C)
CREATE TABLE proveedores (
    id_proveedor        SERIAL PRIMARY KEY,
    rut                 VARCHAR(12) NOT NULL UNIQUE
                            CHECK (fn_validar_rut_chileno(rut)),
    razon_social        VARCHAR(150) NOT NULL,
    giro                VARCHAR(120) NOT NULL,
    direccion           VARCHAR(200) NOT NULL,
    region              VARCHAR(80) NOT NULL,
    comuna              VARCHAR(80) NOT NULL,
    ciudad              VARCHAR(80) NOT NULL,
    telefono            VARCHAR(30),
    banco               VARCHAR(80),
    tipo_cuenta         VARCHAR(40),
    numero_cuenta       VARCHAR(50),
    email_pagos         VARCHAR(120),
    plazo_credito_dias  SMALLINT NOT NULL DEFAULT 30 CHECK (plazo_credito_dias >= 0),
    activo              BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. clientes (Incluye región/comuna/ciudad y Representante Legal — Anexo C)
CREATE TABLE clientes (
    id_cliente                  SERIAL PRIMARY KEY,
    rut                         VARCHAR(12) NOT NULL UNIQUE
                                    CHECK (fn_validar_rut_chileno(rut)),
    razon_social                VARCHAR(150) NOT NULL,
    giro                        VARCHAR(120) NOT NULL,
    direccion                   VARCHAR(200) NOT NULL,
    region                      VARCHAR(80) NOT NULL,
    comuna                      VARCHAR(80) NOT NULL,
    ciudad                      VARCHAR(80) NOT NULL,
    representante_legal_nombre  VARCHAR(150) NOT NULL,
    representante_legal_rut     VARCHAR(12) NOT NULL
                                    CHECK (fn_validar_rut_chileno(representante_legal_rut)),
    activo                      BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en                   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. contactos (Contactos comerciales de Proveedores o Proyectos/Finanzas de Clientes)
CREATE TABLE contactos (
    id_contacto         SERIAL PRIMARY KEY,
    id_cliente          INTEGER REFERENCES clientes(id_cliente)
                            ON DELETE RESTRICT ON UPDATE CASCADE,
    id_proveedor        INTEGER REFERENCES proveedores(id_proveedor)
                            ON DELETE RESTRICT ON UPDATE CASCADE,
    tipo_contacto       VARCHAR(40) NOT NULL CHECK (
                            tipo_contacto IN ('COMERCIAL', 'PROYECTOS', 'FINANZAS', 'OTRO')
                        ),
    nombre_contacto     VARCHAR(120) NOT NULL,
    rut_contacto        VARCHAR(12) CHECK (
                            rut_contacto IS NULL OR fn_validar_rut_chileno(rut_contacto)
                        ),
    cargo               VARCHAR(80) NOT NULL,
    email               VARCHAR(120) NOT NULL,
    telefono            VARCHAR(30),
    es_principal        BOOLEAN NOT NULL DEFAULT FALSE,
    activo              BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_contacto_entidad_exclusiva CHECK (
        (id_cliente IS NOT NULL AND id_proveedor IS NULL) OR
        (id_cliente IS NULL AND id_proveedor IS NOT NULL)
    )
);

-- 7. categorias (Clasificación técnica paramétrica — Anexo C)
CREATE TABLE categorias (
    id_categoria        SERIAL PRIMARY KEY,
    nombre              VARCHAR(80) NOT NULL UNIQUE,
    codigo_prefijo      VARCHAR(10) NOT NULL UNIQUE,
    descripcion         VARCHAR(200),
    activo              BOOLEAN NOT NULL DEFAULT TRUE
);

-- 8. articulos (Stock, Valorización Dual PMP/Lista y última fecha de precio)
CREATE TABLE articulos (
    id_articulo                     SERIAL PRIMARY KEY,
    id_categoria                    INTEGER NOT NULL REFERENCES categorias(id_categoria)
                                        ON DELETE RESTRICT ON UPDATE CASCADE,
    codigo_sku                      VARCHAR(50) NOT NULL UNIQUE,
    codigo_barras                   VARCHAR(80) UNIQUE,
    nombre                          VARCHAR(150) NOT NULL,
    descripcion                     TEXT,
    unidad_medida                   VARCHAR(20) NOT NULL DEFAULT 'UN',
    sector_bodega                   VARCHAR(40) NOT NULL DEFAULT 'BODEGA_CENTRAL',
    ubicacion_bodega                VARCHAR(60) NOT NULL,
    stock_fisico                    NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (stock_fisico >= 0),
    stock_comprometido              NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (stock_comprometido >= 0),
    stock_minimo_critico            NUMERIC(12,2) NOT NULL DEFAULT 1.00 CHECK (stock_minimo_critico >= 0),
    ultimo_costo_compra             NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (ultimo_costo_compra >= 0),
    costo_promedio_pmp              NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (costo_promedio_pmp >= 0),
    precio_lista                    NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (precio_lista >= 0),
    fecha_ultima_actualizacion_precio TIMESTAMPTZ,
    activo                          BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en                       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 9. documentos_compra (Facturas, Boletas, Guías y Notas de Crédito + Descuento General)
CREATE TABLE documentos_compra (
    id_documento_compra     SERIAL PRIMARY KEY,
    id_proveedor            INTEGER NOT NULL REFERENCES proveedores(id_proveedor)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    id_usuario_creador      INTEGER NOT NULL REFERENCES usuarios(id_usuario)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    id_documento_referencia INTEGER REFERENCES documentos_compra(id_documento_compra)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    tipo_doc                VARCHAR(20) NOT NULL CHECK (
                                tipo_doc IN ('FACTURA', 'BOLETA', 'GUIA_DESPACHO', 'NOTA_CREDITO')
                            ),
    folio_documento         VARCHAR(40) NOT NULL,
    fecha_emision           DATE NOT NULL,
    fecha_ingreso           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fecha_vencimiento       DATE,
    subtotal_neto           NUMERIC(14,2) NOT NULL DEFAULT 0.00 CHECK (subtotal_neto >= 0),
    descuento_general_pct   NUMERIC(5,2)  NOT NULL DEFAULT 0.00 CHECK (descuento_general_pct BETWEEN 0 AND 100),
    desc_pronto_pago_pct    NUMERIC(5,2)  NOT NULL DEFAULT 0.00 CHECK (desc_pronto_pago_pct BETWEEN 0 AND 100),
    monto_neto_final        NUMERIC(14,2) NOT NULL DEFAULT 0.00 CHECK (monto_neto_final >= 0),
    monto_iva_total         NUMERIC(14,2) NOT NULL DEFAULT 0.00 CHECK (monto_iva_total >= 0),
    monto_total             NUMERIC(14,2) NOT NULL DEFAULT 0.00 CHECK (monto_total >= 0),
    estado_documento        VARCHAR(20)   NOT NULL DEFAULT 'BORRADOR' CHECK (
                                estado_documento IN ('BORRADOR', 'CONFIRMADO', 'ANULADO')
                            ),
    estado_pago             VARCHAR(20)   NOT NULL DEFAULT 'PENDIENTE' CHECK (
                                estado_pago IN ('PENDIENTE', 'PARCIAL', 'PAGADO', 'ANULADO')
                            ),
    reversa_nc_aplicada     BOOLEAN NOT NULL DEFAULT FALSE,
    observaciones           TEXT,
    CONSTRAINT uq_doc_compra_proveedor_folio UNIQUE (id_proveedor, tipo_doc, folio_documento)
);

-- 10. lineas_compra (Hasta 3 descuentos sucesivos en cascada por producto — RN-11)
CREATE TABLE lineas_compra (
    id_linea_compra         SERIAL PRIMARY KEY,
    id_documento_compra     INTEGER NOT NULL REFERENCES documentos_compra(id_documento_compra)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    id_articulo             INTEGER NOT NULL REFERENCES articulos(id_articulo)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    cantidad                NUMERIC(12,2) NOT NULL CHECK (cantidad > 0),
    precio_unitario_lista   NUMERIC(12,2) NOT NULL CHECK (precio_unitario_lista >= 0),
    desc_1_pct              NUMERIC(5,2)  NOT NULL DEFAULT 0.00 CHECK (desc_1_pct BETWEEN 0 AND 100),
    desc_2_pct              NUMERIC(5,2)  NOT NULL DEFAULT 0.00 CHECK (desc_2_pct BETWEEN 0 AND 100),
    desc_3_pct              NUMERIC(5,2)  NOT NULL DEFAULT 0.00 CHECK (desc_3_pct BETWEEN 0 AND 100),
    costo_unitario_tasado   NUMERIC(12,2) NOT NULL CHECK (costo_unitario_tasado >= 0),
    variacion_margen_pct    NUMERIC(6,2)  NOT NULL DEFAULT 0.00,
    subtotal_linea          NUMERIC(14,2) NOT NULL CHECK (subtotal_linea >= 0),
    observaciones           TEXT
);

-- 11. historial_precios_compra (Normalizado para consultar los últimos 3 precios y fechas — Anexo C)
CREATE TABLE historial_precios_compra (
    id_historial_precio     BIGSERIAL PRIMARY KEY,
    id_articulo             INTEGER NOT NULL REFERENCES articulos(id_articulo)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    id_documento_compra     INTEGER NOT NULL REFERENCES documentos_compra(id_documento_compra)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    costo_unitario_tasado   NUMERIC(12,2) NOT NULL CHECK (costo_unitario_tasado >= 0),
    precio_lista_referencia NUMERIC(12,2) NOT NULL CHECK (precio_lista_referencia >= 0),
    fecha_actualizacion     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 12. presupuestos (Base comercial para apertura de obras — RF-07)
CREATE TABLE presupuestos (
    id_presupuesto      SERIAL PRIMARY KEY,
    id_cliente          INTEGER NOT NULL REFERENCES clientes(id_cliente)
                            ON DELETE RESTRICT ON UPDATE CASCADE,
    id_usuario_emisor   INTEGER NOT NULL REFERENCES usuarios(id_usuario)
                            ON DELETE RESTRICT ON UPDATE CASCADE,
    codigo_presupuesto  VARCHAR(30) NOT NULL UNIQUE,
    fecha_emision       DATE NOT NULL DEFAULT CURRENT_DATE,
    monto_estimado_neto NUMERIC(14,2) NOT NULL CHECK (monto_estimado_neto >= 0),
    margen_esperado_pct NUMERIC(5,2)  NOT NULL DEFAULT 0.00,
    estado              VARCHAR(20)   NOT NULL DEFAULT 'PENDIENTE' CHECK (
                            estado IN ('BORRADOR', 'PENDIENTE', 'APROBADO', 'RECHAZADO')
                        ),
    observaciones       TEXT
);

-- ============================================================================
-- DOMINIO 3: GESTIÓN DE OBRAS, FINANZAS Y BODEGA (CARDEX INMUTABLE)
-- ============================================================================

-- 13. obras (Catálogo cerrado de 8 tipos de servicio y 4 estados oficiales — Anexo C)
CREATE TABLE obras (
    id_obra                 SERIAL PRIMARY KEY,
    id_cliente              INTEGER NOT NULL REFERENCES clientes(id_cliente)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    id_presupuesto          INTEGER REFERENCES presupuestos(id_presupuesto)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    id_supervisor           INTEGER NOT NULL REFERENCES usuarios(id_usuario)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    id_tecnico_responsable  INTEGER REFERENCES usuarios(id_usuario)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    codigo_obra             VARCHAR(30) NOT NULL UNIQUE,
    nombre_proyecto         VARCHAR(150) NOT NULL,
    ubicacion_planta        VARCHAR(200) NOT NULL,
    tipo_servicio           VARCHAR(30) NOT NULL CHECK (
                                tipo_servicio IN (
                                    'PROYECTO',
                                    'MANTENCION',
                                    'CLIMATIZACION',
                                    'ELECTRICO',
                                    'EMERGENCIA',
                                    'GARANTIA',
                                    'REPUESTOS',
                                    'MEJORAS'
                                )
                            ),
    estado_actual           VARCHAR(20) NOT NULL DEFAULT 'EN_PROCESO' CHECK (
                                estado_actual IN (
                                    'EN_PROCESO',
                                    'FINALIZADA',
                                    'SUSPENDIDA',
                                    'CANCELADA'
                                )
                            ),
    fecha_creacion          DATE NOT NULL DEFAULT CURRENT_DATE,
    presupuesto_asignado    NUMERIC(14,2) NOT NULL DEFAULT 0.00 CHECK (presupuesto_asignado >= 0),
    costo_acumulado_real    NUMERIC(14,2) NOT NULL DEFAULT 0.00 CHECK (costo_acumulado_real >= 0),
    horas_hombre_totales    NUMERIC(8,2)  NOT NULL DEFAULT 0.00 CHECK (horas_hombre_totales >= 0),
    creado_en               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 14. historial_estados_obra (Trazabilidad obligatoria de transiciones — RN-07 a RN-10)
CREATE TABLE historial_estados_obra (
    id_historial_estado SERIAL PRIMARY KEY,
    id_obra             INTEGER NOT NULL REFERENCES obras(id_obra)
                            ON DELETE RESTRICT ON UPDATE CASCADE,
    id_usuario          INTEGER NOT NULL REFERENCES usuarios(id_usuario)
                            ON DELETE RESTRICT ON UPDATE CASCADE,
    estado_anterior     VARCHAR(20) CHECK (
                            estado_anterior IS NULL OR
                            estado_anterior IN ('EN_PROCESO', 'FINALIZADA', 'SUSPENDIDA', 'CANCELADA')
                        ),
    estado_nuevo        VARCHAR(20) NOT NULL CHECK (
                            estado_nuevo IN ('EN_PROCESO', 'FINALIZADA', 'SUSPENDIDA', 'CANCELADA')
                        ),
    justificacion_cambio TEXT NOT NULL,
    fecha_transicion    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 15. pagos (Cuentas por cobrar a clientes y cuentas por pagar a proveedores — CU-10)
CREATE TABLE pagos (
    id_pago             SERIAL PRIMARY KEY,
    id_documento_compra INTEGER REFERENCES documentos_compra(id_documento_compra)
                            ON DELETE RESTRICT ON UPDATE CASCADE,
    id_obra             INTEGER REFERENCES obras(id_obra)
                            ON DELETE RESTRICT ON UPDATE CASCADE,
    id_usuario_registro INTEGER NOT NULL REFERENCES usuarios(id_usuario)
                            ON DELETE RESTRICT ON UPDATE CASCADE,
    tipo_flujo          VARCHAR(20) NOT NULL CHECK (tipo_flujo IN ('COBRO_CLIENTE', 'PAGO_PROVEEDOR')),
    monto_pagado        NUMERIC(14,2) NOT NULL CHECK (monto_pagado > 0),
    fecha_pago          DATE NOT NULL DEFAULT CURRENT_DATE,
    medio_pago          VARCHAR(40) NOT NULL,
    comprobante_ref     VARCHAR(80),
    observaciones       TEXT,
    CONSTRAINT chk_pago_origen_exclusivo CHECK (
        (id_documento_compra IS NOT NULL AND id_obra IS NULL AND tipo_flujo = 'PAGO_PROVEEDOR') OR
        (id_obra IS NOT NULL AND id_documento_compra IS NULL AND tipo_flujo = 'COBRO_CLIENTE')
    )
);

-- 16. movimientos_cardex (Cardex inmutable: prohibido DELETE/UPDATE por Trigger — RN-01)
CREATE TABLE movimientos_cardex (
    id_movimiento           BIGSERIAL PRIMARY KEY,
    id_articulo             INTEGER NOT NULL REFERENCES articulos(id_articulo)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    id_usuario              INTEGER NOT NULL REFERENCES usuarios(id_usuario)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    id_documento_compra     INTEGER REFERENCES documentos_compra(id_documento_compra)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    id_obra                 INTEGER REFERENCES obras(id_obra)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    tipo_movimiento         VARCHAR(25) NOT NULL CHECK (
                                tipo_movimiento IN (
                                    'INGRESO',
                                    'EGRESO_OBRA',
                                    'REVERSA',
                                    'MERMA',
                                    'DEVOLUCION_PROVEEDOR',
                                    'USO_INTERNO',
                                    'CAMBIO_OBRA',
                                    'AJUSTE_INVENTARIO'
                                )
                            ),
    fecha_hora              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cantidad                NUMERIC(12,2) NOT NULL CHECK (cantidad <> 0),
    saldo_stock_resultante  NUMERIC(12,2) NOT NULL CHECK (saldo_stock_resultante >= 0),
    costo_pmp_momento       NUMERIC(12,2) NOT NULL CHECK (costo_pmp_momento >= 0),
    precio_lista_momento    NUMERIC(12,2) NOT NULL CHECK (precio_lista_momento >= 0),
    destino_uso_interno     VARCHAR(120),
    observaciones           TEXT
);

-- 17. reversas_cardex (Única vía legal de corrección autorizada por Admin General — RN-02, RN-03)
CREATE TABLE reversas_cardex (
    id_reversa              SERIAL PRIMARY KEY,
    id_movimiento_orig      BIGINT NOT NULL REFERENCES movimientos_cardex(id_movimiento)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    id_movimiento_comp      BIGINT UNIQUE REFERENCES movimientos_cardex(id_movimiento)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    id_usuario_solicitante  INTEGER NOT NULL REFERENCES usuarios(id_usuario)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    id_admin_autorizador    INTEGER REFERENCES usuarios(id_usuario)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    motivo_obligatorio      TEXT NOT NULL,
    estado_reversa          VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE' CHECK (
                                estado_reversa IN ('PENDIENTE', 'APROBADA', 'RECHAZADA')
                            ),
    fecha_solicitud         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fecha_resolucion        TIMESTAMPTZ
);

-- 18. egresos_obra (Valorización dual: rebaja bodega a PMP e imputa obra a Precio Lista — RN-14)
CREATE TABLE egresos_obra (
    id_egreso_obra      SERIAL PRIMARY KEY,
    id_obra             INTEGER NOT NULL REFERENCES obras(id_obra)
                            ON DELETE RESTRICT ON UPDATE CASCADE,
    id_movimiento       BIGINT NOT NULL UNIQUE REFERENCES movimientos_cardex(id_movimiento)
                            ON DELETE RESTRICT ON UPDATE CASCADE,
    id_articulo         INTEGER NOT NULL REFERENCES articulos(id_articulo)
                            ON DELETE RESTRICT ON UPDATE CASCADE,
    cantidad_despachada NUMERIC(12,2) NOT NULL CHECK (cantidad_despachada > 0),
    costo_imputado_pmp  NUMERIC(14,2) NOT NULL CHECK (costo_imputado_pmp >= 0),
    valor_imputado_lista NUMERIC(14,2) NOT NULL CHECK (valor_imputado_lista >= 0),
    receptor_nombre     VARCHAR(120),
    fecha_despacho      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 19. inventarios_fisicos (Cabecera de toma de inventario físico — CU-08, RF-04)
CREATE TABLE inventarios_fisicos (
    id_inventario           SERIAL PRIMARY KEY,
    id_usuario_bodega       INTEGER NOT NULL REFERENCES usuarios(id_usuario)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    fecha_apertura          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fecha_cierre            TIMESTAMPTZ,
    estado                  VARCHAR(20) NOT NULL DEFAULT 'EN_PROCESO' CHECK (
                                estado IN ('EN_PROCESO', 'FINALIZADO')
                            ),
    observaciones_auditoria TEXT
);

-- 20. detalles_inventario (Cuadratura stock sistema vs. físico y mermas)
CREATE TABLE detalles_inventario (
    id_detalle_inv          SERIAL PRIMARY KEY,
    id_inventario           INTEGER NOT NULL REFERENCES inventarios_fisicos(id_inventario)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    id_articulo             INTEGER NOT NULL REFERENCES articulos(id_articulo)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    stock_sistema_esperado  NUMERIC(12,2) NOT NULL CHECK (stock_sistema_esperado >= 0),
    stock_fisico_contado    NUMERIC(12,2) NOT NULL CHECK (stock_fisico_contado >= 0),
    diferencia_merma        NUMERIC(12,2) NOT NULL,
    ajuste_aplicado         BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT uq_inventario_articulo UNIQUE (id_inventario, id_articulo)
);

-- ============================================================================
-- DOMINIO 4: OPERACIÓN MÓVIL EN TERRENO (PWA OFFLINE, EVIDENCIAS Y CHECKLISTS)
-- ============================================================================

-- 21. hojas_servicio (Idempotencia Offline mediante uuid_offline_pwa — HU-05, RN-19)
CREATE TABLE hojas_servicio (
    id_hoja_servicio        SERIAL PRIMARY KEY,
    id_obra                 INTEGER NOT NULL REFERENCES obras(id_obra)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    id_tecnico              INTEGER NOT NULL REFERENCES usuarios(id_usuario)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    uuid_offline_pwa        UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    fecha_inicio            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fecha_termino           TIMESTAMPTZ,
    horas_hombre_registradas NUMERIC(6,2) NOT NULL DEFAULT 0.00 CHECK (horas_hombre_registradas >= 0),
    gps_latitud             NUMERIC(9,6),
    gps_longitud            NUMERIC(9,6),
    sincronizado_offline    BOOLEAN NOT NULL DEFAULT FALSE,
    observaciones           TEXT
);

-- 22. consumos_material (Materiales reportados en terreno + bandera de discrepancia — RN-19)
CREATE TABLE consumos_material (
    id_consumo                  SERIAL PRIMARY KEY,
    id_hoja_servicio            INTEGER NOT NULL REFERENCES hojas_servicio(id_hoja_servicio)
                                    ON DELETE RESTRICT ON UPDATE CASCADE,
    id_articulo                 INTEGER NOT NULL REFERENCES articulos(id_articulo)
                                    ON DELETE RESTRICT ON UPDATE CASCADE,
    cantidad_utilizada          NUMERIC(12,2) NOT NULL CHECK (cantidad_utilizada > 0),
    alerta_discrepancia_stock   BOOLEAN NOT NULL DEFAULT FALSE,
    observacion_discrepancia    VARCHAR(200)
);

-- 23. evidencias (Enlace a objetos no estructurados en Cloud S3 + Sello SHA-256 — Ley 19.799)
CREATE TABLE evidencias (
    id_evidencia            SERIAL PRIMARY KEY,
    id_hoja_servicio        INTEGER NOT NULL REFERENCES hojas_servicio(id_hoja_servicio)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    tipo_evidencia          VARCHAR(25) NOT NULL CHECK (
                                tipo_evidencia IN ('FOTO_WEBP', 'FIRMA_PNG', 'PDF_COMPROBANTE')
                            ),
    s3_object_key_uri       VARCHAR(255) NOT NULL,
    hash_sha256_integridad  CHAR(64) NOT NULL,
    peso_kb                 INTEGER NOT NULL CHECK (peso_kb > 0),
    firmante_nombre         VARCHAR(120),
    firmante_rut            VARCHAR(12) CHECK (
                                firmante_rut IS NULL OR fn_validar_rut_chileno(firmante_rut)
                            ),
    fecha_subida            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 24. checklists (Estructura semi-estructurada JSONB para botones Sí/No/Falla — HU-05)
CREATE TABLE checklists (
    id_checklist            SERIAL PRIMARY KEY,
    id_hoja_servicio        INTEGER NOT NULL REFERENCES hojas_servicio(id_hoja_servicio)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    tipo_equipo_frigorifico VARCHAR(80) NOT NULL,
    respuestas_botones_json JSONB NOT NULL,
    aprobado_operativo      BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_registro          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- VISTAS ANALÍTICAS Y CONSULTA DE ÚLTIMOS 3 PRECIOS HISTÓRICOS (ANEXO C)
-- ============================================================================

CREATE OR REPLACE VIEW vw_ultimos_3_precios_articulos AS
SELECT
    id_articulo,
    id_documento_compra,
    costo_unitario_tasado,
    precio_lista_referencia,
    fecha_actualizacion,
    posicion_precio
FROM (
    SELECT
        hpc.id_articulo,
        hpc.id_documento_compra,
        hpc.costo_unitario_tasado,
        hpc.precio_lista_referencia,
        hpc.fecha_actualizacion,
        ROW_NUMBER() OVER (
            PARTITION BY hpc.id_articulo
            ORDER BY hpc.fecha_actualizacion DESC, hpc.id_historial_precio DESC
        ) AS posicion_precio
    FROM historial_precios_compra hpc
) ranked
WHERE posicion_precio <= 3;

-- ============================================================================
-- TRIGGERS DE INTEGRIDAD, INMUTABILIDAD Y REGLAS DE NEGOCIO (PL/pgSQL)
-- ============================================================================

-- 1. Trigger Antifraude: Prohibición absoluta de DELETE en tablas críticas (RN-01)
CREATE OR REPLACE FUNCTION fn_prohibir_borrado_fisico()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'VIOLACIÓN DE SEGURIDAD (RN-01): El borrado físico (DELETE) está bloqueado en la tabla %. Utilice reversa autorizada o inactivación lógica.', TG_TABLE_NAME
        USING ERRCODE = '42501';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_no_delete_cardex
    BEFORE DELETE OR UPDATE ON movimientos_cardex
    FOR EACH ROW EXECUTE FUNCTION fn_prohibir_borrado_fisico();

CREATE TRIGGER trg_no_delete_bitacora
    BEFORE DELETE OR UPDATE ON bitacora_auditoria
    FOR EACH ROW EXECUTE FUNCTION fn_prohibir_borrado_fisico();

CREATE TRIGGER trg_no_delete_documentos_compra
    BEFORE DELETE ON documentos_compra
    FOR EACH ROW EXECUTE FUNCTION fn_prohibir_borrado_fisico();

CREATE TRIGGER trg_no_delete_obras
    BEFORE DELETE ON obras
    FOR EACH ROW EXECUTE FUNCTION fn_prohibir_borrado_fisico();

CREATE TRIGGER trg_no_delete_egresos_obra
    BEFORE DELETE ON egresos_obra
    FOR EACH ROW EXECUTE FUNCTION fn_prohibir_borrado_fisico();

CREATE TRIGGER trg_no_delete_pagos
    BEFORE DELETE ON pagos
    FOR EACH ROW EXECUTE FUNCTION fn_prohibir_borrado_fisico();

-- 2. Trigger de Historial de Precios: Registra cada precio de compra y fecha (Anexo C)
CREATE OR REPLACE FUNCTION fn_registrar_historial_precio_compra()
RETURNS TRIGGER AS $$
DECLARE
    v_tipo_doc VARCHAR(20);
BEGIN
    SELECT tipo_doc INTO v_tipo_doc
    FROM documentos_compra
    WHERE id_documento_compra = NEW.id_documento_compra;

    -- Solo registra precios históricos en documentos de ingreso (no en Notas de Crédito)
    IF v_tipo_doc IN ('FACTURA', 'BOLETA', 'GUIA_DESPACHO') THEN
        INSERT INTO historial_precios_compra (
            id_articulo,
            id_documento_compra,
            costo_unitario_tasado,
            precio_lista_referencia,
            fecha_actualizacion
        ) VALUES (
            NEW.id_articulo,
            NEW.id_documento_compra,
            NEW.costo_unitario_tasado,
            NEW.precio_unitario_lista,
            NOW()
        );

        UPDATE articulos
        SET ultimo_costo_compra = NEW.costo_unitario_tasado,
            precio_lista = CASE
                WHEN NEW.precio_unitario_lista > 0 THEN NEW.precio_unitario_lista
                ELSE precio_lista
            END,
            fecha_ultima_actualizacion_precio = NOW()
        WHERE id_articulo = NEW.id_articulo;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_registrar_historial_precio
    AFTER INSERT ON lineas_compra
    FOR EACH ROW EXECUTE FUNCTION fn_registrar_historial_precio_compra();

-- 3. Trigger de Nota de Crédito (RN-13): Reversión automática de stock y recálculo PMP
CREATE OR REPLACE FUNCTION fn_procesar_nota_credito()
RETURNS TRIGGER AS $$
DECLARE
    v_linea         RECORD;
    v_art           RECORD;
    v_nuevo_stock   NUMERIC(12,2);
    v_nuevo_pmp     NUMERIC(12,2);
    v_valor_actual  NUMERIC(14,2);
    v_valor_reversa NUMERIC(14,2);
BEGIN
    IF NEW.tipo_doc = 'NOTA_CREDITO'
       AND NEW.estado_documento = 'CONFIRMADO'
       AND NEW.reversa_nc_aplicada = FALSE THEN

        FOR v_linea IN
            SELECT id_articulo, cantidad, costo_unitario_tasado, precio_unitario_lista
            FROM lineas_compra
            WHERE id_documento_compra = NEW.id_documento_compra
        LOOP
            -- Bloqueo pesimista de fila para concurrencia ACID (RN-17)
            SELECT stock_fisico, costo_promedio_pmp, precio_lista
            INTO v_art
            FROM articulos
            WHERE id_articulo = v_linea.id_articulo
            FOR UPDATE;

            IF v_art.stock_fisico < v_linea.cantidad THEN
                RAISE EXCEPTION 'RN-13 / Stock insuficiente para aplicar Nota de Crédito sobre artículo % (Stock actual: %, Reversa solicitada: %).',
                    v_linea.id_articulo, v_art.stock_fisico, v_linea.cantidad;
            END IF;

            v_nuevo_stock := ROUND(v_art.stock_fisico - v_linea.cantidad, 2);
            v_valor_actual := v_art.stock_fisico * v_art.costo_promedio_pmp;
            v_valor_reversa := v_linea.cantidad * v_linea.costo_unitario_tasado;

            IF v_nuevo_stock > 0 THEN
                v_nuevo_pmp := GREATEST(0.00, ROUND((v_valor_actual - v_valor_reversa) / v_nuevo_stock, 2));
            ELSE
                v_nuevo_pmp := v_art.costo_promedio_pmp;
            END IF;

            UPDATE articulos
            SET stock_fisico = v_nuevo_stock,
                costo_promedio_pmp = v_nuevo_pmp
            WHERE id_articulo = v_linea.id_articulo;

            INSERT INTO movimientos_cardex (
                id_articulo,
                id_usuario,
                id_documento_compra,
                tipo_movimiento,
                cantidad,
                saldo_stock_resultante,
                costo_pmp_momento,
                precio_lista_momento,
                observaciones
            ) VALUES (
                v_linea.id_articulo,
                NEW.id_usuario_creador,
                NEW.id_documento_compra,
                'REVERSA',
                -v_linea.cantidad,
                v_nuevo_stock,
                v_nuevo_pmp,
                v_art.precio_lista,
                'Reversión automática por Nota de Crédito folio ' || NEW.folio_documento
            );
        END LOOP;

        UPDATE documentos_compra
        SET reversa_nc_aplicada = TRUE
        WHERE id_documento_compra = NEW.id_documento_compra;

        INSERT INTO bitacora_auditoria (
            id_usuario,
            entidad_afectada,
            id_registro_afectado,
            accion,
            valor_nuevo_json,
            motivo
        ) VALUES (
            NEW.id_usuario_creador,
            'documentos_compra',
            NEW.id_documento_compra::TEXT,
            'REVERSA_NOTA_CREDITO',
            jsonb_build_object(
                'folio_nc', NEW.folio_documento,
                'doc_referencia', NEW.id_documento_referencia,
                'monto_total', NEW.monto_total
            ),
            'Aplicación automática de Nota de Crédito sobre stock y costo PMP (RN-13)'
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_aplicar_nota_credito
    AFTER INSERT OR UPDATE OF estado_documento ON documentos_compra
    FOR EACH ROW EXECUTE FUNCTION fn_procesar_nota_credito();

-- ============================================================================
-- ÍNDICES DE OPTIMIZACIÓN (B-TREE PARA CONSULTAS KPI + GIN PARA JSONB)
-- ============================================================================

CREATE INDEX idx_usuarios_rol ON usuarios(id_rol);
CREATE INDEX idx_articulos_categoria ON articulos(id_categoria);
CREATE INDEX idx_articulos_stock_critico ON articulos(stock_fisico, stock_minimo_critico) WHERE activo = TRUE;
CREATE INDEX idx_doc_compra_proveedor_fecha ON documentos_compra(id_proveedor, fecha_emision DESC);
CREATE INDEX idx_doc_compra_vencimiento ON documentos_compra(fecha_vencimiento) WHERE estado_pago IN ('PENDIENTE', 'PARCIAL');
CREATE INDEX idx_lineas_compra_doc ON lineas_compra(id_documento_compra);
CREATE INDEX idx_historial_precios_art_fecha ON historial_precios_compra(id_articulo, fecha_actualizacion DESC);
CREATE INDEX idx_obras_estado_cliente ON obras(estado_actual, id_cliente);
CREATE INDEX idx_obras_tecnico ON obras(id_tecnico_responsable);
CREATE INDEX idx_cardex_articulo_fecha ON movimientos_cardex(id_articulo, fecha_hora DESC);
CREATE INDEX idx_cardex_obra ON movimientos_cardex(id_obra) WHERE id_obra IS NOT NULL;
CREATE INDEX idx_hojas_servicio_obra ON hojas_servicio(id_obra);
CREATE INDEX idx_evidencias_hoja ON evidencias(id_hoja_servicio);

-- Índices invertidos GIN para búsquedas rápidas en columnas semi-estructuradas JSONB
CREATE INDEX idx_roles_permisos_gin ON roles USING GIN (permisos_rbac_json);
CREATE INDEX idx_bitacora_anterior_gin ON bitacora_auditoria USING GIN (valor_anterior_json);
CREATE INDEX idx_bitacora_nuevo_gin ON bitacora_auditoria USING GIN (valor_nuevo_json);
CREATE INDEX idx_checklists_respuestas_gin ON checklists USING GIN (respuestas_botones_json);
-- =====================================================================
-- Sistema de gestión de propiedad horizontal - Tópicos avanzados
-- Motor: PostgreSQL (Neon). Ejecutar DESPUÉS de 01_DDL y 02_DML,
-- conectado con el usuario DUEÑO de la base de datos.
-- Contenido: roles y permisos, procedimiento, trigger, vista de estado
-- financiero y estrategia de optimización (índices).
-- Las pruebas por usuario están en 05_Pruebas_Roles.sql
-- =====================================================================

-- 0. Limpieza (permite volver a ejecutar el script)
DROP PROCEDURE IF EXISTS sp_procesar_pago_admin(INT, INT, DECIMAL, VARCHAR);
DROP USER IF EXISTS admin_pedro;
DROP USER IF EXISTS vigilante_luis;
DROP USER IF EXISTS secretaria_ana;
DROP USER IF EXISTS prop_apto101;
DROP ROLE IF EXISTS rol_secretaria;
DROP ROLE IF EXISTS rol_vigilante;
DROP ROLE IF EXISTS rol_administrador;
DROP ROLE IF EXISTS rol_propietario;

-- 1. Roles y permisos
CREATE ROLE rol_secretaria;
CREATE ROLE rol_vigilante;
CREATE ROLE rol_administrador;
CREATE ROLE rol_propietario;

-- el administrador puede hacer todo
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO rol_administrador;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO rol_administrador; -- ids autoincrementables

-- secretaria
GRANT SELECT, INSERT, UPDATE ON residente, vehiculo, parqueadero, apartamento, reserva TO rol_secretaria;

-- vigilante
GRANT SELECT ON residente, apartamento, vehiculo, parqueadero, reserva TO rol_vigilante;
GRANT INSERT, SELECT ON ingreso_visita TO rol_vigilante;

-- propietario
GRANT SELECT ON apartamento, cuota_admin, zona_comun TO rol_propietario;

CREATE USER admin_pedro    WITH PASSWORD 'Admin_PH26*';
GRANT rol_administrador TO admin_pedro;

CREATE USER vigilante_luis WITH PASSWORD 'Vigilante_PH26*';
GRANT rol_vigilante TO vigilante_luis;

CREATE USER secretaria_ana WITH PASSWORD 'Secretaria_PH26*';
GRANT rol_secretaria TO secretaria_ana;

CREATE USER prop_apto101   WITH PASSWORD 'Prop101_PH26*';
GRANT rol_propietario TO prop_apto101;

-- 2. Procedimiento almacenado: o se paga la cuota COMPLETA o no se paga
CREATE OR REPLACE PROCEDURE sp_procesar_pago_admin(
    p_id_apartamento INT,
    p_id_cuota       INT,
    p_monto          DECIMAL,
    p_metodo         VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER            -- se ejecuta con los permisos del dueño, no del que llama
SET search_path = public    -- evita que un usuario "engañe" al procedimiento con otro esquema
AS $$
DECLARE
    v_valor_cuota DECIMAL(12,2);
    v_nuevo_id    INT;
BEGIN
    -- 1. Consultar cuánto vale la cuota realmente
    SELECT valor INTO v_valor_cuota FROM cuota_admin WHERE id_cuota = p_id_cuota;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ERROR: La cuota % no existe.', p_id_cuota;
    END IF;

    -- 2. REGLA ESTRICTA: si el monto no es EXACTAMENTE la cuota, se rechaza todo
    IF p_monto <> v_valor_cuota THEN
        RAISE EXCEPTION 'ERROR: Transacción rechazada. El pago debe ser exactamente de $ %', v_valor_cuota;
    END IF;

    -- 3. No se puede pagar dos veces la misma cuota del mismo apartamento
    IF EXISTS (SELECT 1 FROM pago WHERE id_apartamento = p_id_apartamento AND id_cuota = p_id_cuota) THEN
        RAISE EXCEPTION 'ERROR: La cuota % del apartamento % ya fue pagada.', p_id_cuota, p_id_apartamento;
    END IF;

    -- 4. Calcular el siguiente ID
    SELECT COALESCE(MAX(id_pago), 0) + 1 INTO v_nuevo_id FROM pago;

    -- 5. Registrar el pago (el trigger deja la auditoría automáticamente)
    INSERT INTO pago (id_pago, id_apartamento, id_cuota, fecha_pago, monto_pagado, metodo_pago)
    VALUES (v_nuevo_id, p_id_apartamento, p_id_cuota, CURRENT_DATE, p_monto, p_metodo);
END;
$$;

-- el propietario no tiene permiso de INSERT en pago: solo puede pagar a través del procedimiento
GRANT EXECUTE ON PROCEDURE sp_procesar_pago_admin(INT, INT, DECIMAL, VARCHAR) TO rol_propietario;

-- 3. Trigger de auditoría: cada pago registrado deja una fila en auditoria_pago
-- SESSION_USER = usuario con el que se abrió la conexión (quien realmente pagó).
-- (CURRENT_USER mostraría al dueño del procedimiento por el SECURITY DEFINER.)
CREATE OR REPLACE FUNCTION fn_auditar_pago()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO auditoria_pago (
        fecha_hora, usuario_bd, origen, operacion, resultado, codigo_error,
        id_apartamento, id_cuota, id_pago, monto_intentado, monto_aplicado,
        saldo_pendiente, detalle
    ) VALUES (
        CURRENT_TIMESTAMP, SESSION_USER, 'TRIGGER', 'INSERT', 'EXITOSO', NULL,
        NEW.id_apartamento, NEW.id_cuota, NEW.id_pago, NEW.monto_pagado, NEW.monto_pagado, 0,
        'Pago procesado.'
    );

    RAISE NOTICE 'ÉXITO: Estimado propietario, su pago de administración se ha registrado correctamente.';

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_despues_insert_pago ON pago;
CREATE TRIGGER trg_despues_insert_pago
AFTER INSERT ON pago
FOR EACH ROW
EXECUTE PROCEDURE fn_auditar_pago();

-- 4. Vista: estado financiero de cada apartamento (no se guarda, se calcula)
-- "En deuda" = le falta el pago de alguna cuota del periodo actual o de periodos anteriores.
-- Como los pagos siempre son completos, basta con saber si existe el pago.
CREATE OR REPLACE VIEW vw_estado_financiero AS
SELECT  a.id_apartamento,
        t.nombre_torre,
        a.numero_apto,
        COUNT(c.id_cuota) FILTER (WHERE p.id_pago IS NULL) AS cuotas_sin_pagar,
        CASE WHEN COUNT(c.id_cuota) FILTER (WHERE p.id_pago IS NULL) = 0
             THEN 'Al día' ELSE 'En deuda' END             AS estado_financiero
FROM apartamento a
INNER JOIN torre t       ON t.id_torre = a.id_torre
INNER JOIN cuota_admin c ON c.periodo <= TO_CHAR(CURRENT_DATE, 'YYYY-MM')
LEFT  JOIN pago p        ON p.id_apartamento = a.id_apartamento
                        AND p.id_cuota = c.id_cuota
GROUP BY a.id_apartamento, t.nombre_torre, a.numero_apto;

GRANT SELECT ON vw_estado_financiero TO rol_administrador, rol_secretaria;

-- Verificación (conectado como dueño):
SELECT estado_financiero, COUNT(*) AS apartamentos
FROM vw_estado_financiero
GROUP BY estado_financiero;

-- 5. ESTRATEGIA DE OPTIMIZACIÓN (índices)
DROP TABLE IF EXISTS pago_prueba;

CREATE TABLE pago_prueba (LIKE pago INCLUDING DEFAULTS);
ALTER TABLE pago_prueba ADD PRIMARY KEY (id_pago);

INSERT INTO pago_prueba (id_pago, id_apartamento, id_cuota, fecha_pago, monto_pagado, metodo_pago)
SELECT  g,
        1 + (random() * 1999)::int,                          -- 2000 apartamentos
        1 + (random() * 199)::int,                           -- 200 cuotas
        DATE '2017-01-01' + (random() * 3600)::int,          -- ~10 años de pagos
        ROUND((150000 + random() * 50000)::numeric, 2),
        (ARRAY['Efectivo','Transferencia','PSE','Tarjeta débito','Tarjeta crédito'])[1 + (random() * 4)::int]
FROM generate_series(1, 400000) AS g;

ANALYZE pago_prueba;   -- actualiza las estadísticas que usa el optimizador

SELECT COUNT(*) AS filas_prueba, MIN(fecha_pago) AS desde, MAX(fecha_pago) AS hasta FROM pago_prueba;


-- PASO 1: ANTES del índice (línea base)
-- Consulta típica: recaudo de un solo mes. Se espera "Seq Scan".
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) AS pagos, SUM(monto_pagado) AS recaudo
FROM pago_prueba
WHERE fecha_pago BETWEEN DATE '2026-10-01' AND DATE '2026-10-31';


-- PASO 2: ¿Y si usamos un índice HASH? (demostración de por qué NO)
-- Se espera que el optimizador lo ignore y siga con "Seq Scan",
-- porque hash no sabe resolver rangos.

CREATE INDEX idx_prueba_hash_fecha ON pago_prueba USING hash (fecha_pago);
ANALYZE pago_prueba;

EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) AS pagos, SUM(monto_pagado) AS recaudo
FROM pago_prueba
WHERE fecha_pago BETWEEN DATE '2026-10-01' AND DATE '2026-10-31';

DROP INDEX idx_prueba_hash_fecha;



-- PASO 3: DESPUÉS del índice B-tree
-- Se espera "Index Scan" o "Bitmap Index Scan": solo se leen las páginas
-- del mes consultado y no las de los 10 años.

CREATE INDEX idx_prueba_btree_fecha ON pago_prueba USING btree (fecha_pago);
ANALYZE pago_prueba;

EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) AS pagos, SUM(monto_pagado) AS recaudo
FROM pago_prueba
WHERE fecha_pago BETWEEN DATE '2026-10-01' AND DATE '2026-10-31';



-- PASO 4: índice complementario sobre la llave foránea id_cuota
-- Consulta típica: todos los pagos de una cuota (base de las consultas 2 y 3).

-- 4.a ANTES
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) AS pagos, SUM(monto_pagado) AS recaudo
FROM pago_prueba
WHERE id_cuota = 150;

-- 4.b DESPUÉS
CREATE INDEX idx_prueba_btree_cuota ON pago_prueba USING btree (id_cuota);
ANALYZE pago_prueba;

EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) AS pagos, SUM(monto_pagado) AS recaudo
FROM pago_prueba
WHERE id_cuota = 150;



-- PASO 5: costo del índice (tamaño en disco)
-- Todo índice ocupa espacio y hace más lentos los INSERT/UPDATE. Aquí es
-- aceptable: pago recibe pocas escrituras (una por apartamento al mes) y
-- muchísimas lecturas de reportes.

SELECT  indexrelname                                 AS indice,
        pg_size_pretty(pg_relation_size(indexrelid)) AS tamano
FROM pg_stat_user_indexes
WHERE relname = 'pago_prueba'
ORDER BY indexrelname;

SELECT pg_size_pretty(pg_relation_size('pago_prueba')) AS tamano_tabla;


-- PASO 6: limpiar la tabla de prueba

DROP TABLE pago_prueba;

-- PASO 7: INDICES DEFINITIVOS sobre la tabla real "pago"
-- (esto es lo que queda en la base de datos del proyecto)

CREATE INDEX IF NOT EXISTS idx_pago_fecha_pago ON pago USING btree (fecha_pago);
CREATE INDEX IF NOT EXISTS idx_pago_id_cuota   ON pago USING btree (id_cuota);

-- Verificación: lista los índices de la tabla pago
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'pago'
ORDER BY indexname;
DROP ROLE IF EXISTS rol_secretaria;
DROP ROLE IF EXISTS rol_vigilante;
DROP ROLE IF EXISTS rol_administrador;
DROP ROLE IF EXISTS rol_propietario;

CREATE ROLE rol_secretaria;
CREATE ROLE rol_vigilante;
CREATE ROLE rol_administrador;
CREATE ROLE rol_propietario;

-- permisos al admin de hacer todo
GRANT ALL PRIVILEGES ON ALL tables IN SCHEMA public TO rol_administrador;
GRANT ALL PRIVILEGES ON ALL sequences IN SCHEMA public TO rol_administrador; --lo que tiene ids autoincrementables

--permisos secretaria
GRANT SELECT, INSERT, UPDATE ON residente, vehiculo, parqueadero, apartamento, reserva TO rol_secretaria;

--permisos vigilante
GRANT SELECT  ON residente, apartamento, vehiculo, parqueadero, reserva TO rol_vigilante;
GRANT INSERT, SELECT ON ingreso_visita TO rol_vigilante;

--permisos propietario
GRANT SELECT ON apartamento, cuota_admin, zona_comun TO rol_propietario;

CREATE USER admin_pedro WITH password 'Admin_PH26*';
GRANT rol_administrador TO admin_pedro;

CREATE USER vigilante_luis WITH password 'Vigilante_PH26*';
GRANT rol_vigilante TO vigilante_luis;

CREATE USER secretaria_ana WITH password 'Secretaria_PH26*';
GRANT rol_secretaria TO secretaria_ana;

CREATE USER prop_apto101 WITH password 'Prop101_PH26*';
GRANT rol_propietario TO prop_apto101;

--procedimiento almacenado para que solo se pueda pagar completo o no se pague

CREATE OR REPLACE PROCEDURE sp_procesar_pago_admin(
    p_id_apartamento INT,
    p_id_cuota INT,
    p_monto DECIMAL,
    p_metodo VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER -- Permite ejecutar con permisos elevados encapsulados
AS $$
DECLARE
    v_valor_cuota DECIMAL(12,2);
    v_nuevo_id INT;
BEGIN
    -- 1. Consultar cuánto vale la cuota realmente
    SELECT valor INTO v_valor_cuota FROM cuota_admin WHERE id_cuota = p_id_cuota;

    -- 2. REGLA ESTRICTA: Si el monto no es EXACTAMENTE la cuota, bloqueamos todo
    IF p_monto <> v_valor_cuota THEN
        RAISE EXCEPTION 'ERROR: Transacción rechazada. El pago debe ser exactamente de $ %', v_valor_cuota;
    END IF;

    -- 3. Calcular el siguiente ID manualmente (Solución al error null)
    SELECT COALESCE(MAX(id_pago), 0) + 1 INTO v_nuevo_id FROM pago;

    -- 4. Insertar el pago incluyendo el id calculado
    INSERT INTO pago (id_pago, id_apartamento, id_cuota, fecha_pago, monto_pagado, metodo_pago)
    VALUES (v_nuevo_id, p_id_apartamento, p_id_cuota, CURRENT_DATE, p_monto, p_metodo);
END;
$$;

-- Permiso vital para que el propietario pueda pagar
GRANT EXECUTE ON PROCEDURE sp_procesar_pago_admin(INT, INT, DECIMAL, VARCHAR) TO rol_propietario;

--trigger y funcion 
CREATE OR replace FUNCTION fn_auditar_pago()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO auditoria_pago (
        fecha_hora, usuario_bd, origen, operacion, resultado, codigo_error, 
        id_apartamento, id_cuota, id_pago, monto_intentado, monto_aplicado, 
        saldo_pendiente, detalle
    ) VALUES (
        CURRENT_TIMESTAMP, CURRENT_USER, 'TRIGGER', 'INSERT', 'EXITOSO', NULL,
        NEW.id_apartamento, NEW.id_cuota, NEW.id_pago, NEW.monto_pagado, NEW.monto_pagado, 0,
        'Pago procesado.'
    );

    -- Mensaje verde de éxito en la consola de DBeaver
    RAISE NOTICE 'ÉXITO: Estimado propietario, su pago de administración se ha registrado correctamente.';

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_despues_insert_pago
AFTER INSERT ON pago
FOR EACH ROW
EXECUTE PROCEDURE fn_auditar_pago();


--PRUEBA VIGILANTE
SELECT placa, marca FROM vehiculo; --exitoso
SELECT * FROM cuota_admin; --error porque no se puede

--PRUEBA PROPIETARIO
call sp_procesar_pago_admin(1, 1, 150000.00, 'PSE'); --error pago incompleto
CALL sp_procesar_pago_admin(1, 1, 185000.00, 'PSE'); --pago exitoso

-- ver zonas comunes info
SELECT nombre_zona, capacidad, tarifa_hora FROM zona_comun;

-- ver visitas, error
SELECT * FROM ingreso_visita;

--PRUEBA SECRETARIA
UPDATE residente 
SET correo = 'nuevo_correo_2026@correo.com' 
WHERE id_residente = 1;

DELETE FROM reserva WHERE id_reserva = 1; --error
SELECT * FROM cuota_admin; --error

--PRUEBA ADMIN
SELECT * FROM apartamento;

SELECT * FROM cuota_admin;

UPDATE zona_comun 
SET tarifa_hora = 60000.00 
WHERE id_zona = 1;

DELETE FROM reserva WHERE id_reserva = 2;


--ESTRATEGIA DE OPTIMIZACION
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


-- ---------------------------------------------------------------------
-- PASO 1: ANTES del índice (línea base)
-- Consulta típica: recaudo de un solo mes. Se espera "Seq Scan".
-- ---------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) AS pagos, SUM(monto_pagado) AS recaudo
FROM pago_prueba
WHERE fecha_pago BETWEEN DATE '2026-10-01' AND DATE '2026-10-31';


-- ---------------------------------------------------------------------
-- PASO 2: ¿Y si usamos un índice HASH? (demostración de por qué NO)
-- Se espera que el optimizador lo ignore y siga con "Seq Scan",
-- porque hash no sabe resolver rangos.
-- ---------------------------------------------------------------------
CREATE INDEX idx_prueba_hash_fecha ON pago_prueba USING hash (fecha_pago);
ANALYZE pago_prueba;

EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) AS pagos, SUM(monto_pagado) AS recaudo
FROM pago_prueba
WHERE fecha_pago BETWEEN DATE '2026-10-01' AND DATE '2026-10-31';

DROP INDEX idx_prueba_hash_fecha;


-- ---------------------------------------------------------------------
-- PASO 3: DESPUÉS del índice B-tree
-- Se espera "Index Scan" o "Bitmap Index Scan": solo se leen las páginas
-- del mes consultado y no las de los 10 años.
-- ---------------------------------------------------------------------
CREATE INDEX idx_prueba_btree_fecha ON pago_prueba USING btree (fecha_pago);
ANALYZE pago_prueba;

EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) AS pagos, SUM(monto_pagado) AS recaudo
FROM pago_prueba
WHERE fecha_pago BETWEEN DATE '2026-10-01' AND DATE '2026-10-31';


-- ---------------------------------------------------------------------
-- PASO 4: índice complementario sobre la llave foránea id_cuota
-- Consulta típica: todos los pagos de una cuota (base de las consultas 2 y 3).
-- ---------------------------------------------------------------------
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


-- ---------------------------------------------------------------------
-- PASO 5: costo del índice (tamaño en disco)
-- Todo índice ocupa espacio y hace más lentos los INSERT/UPDATE. Aquí es
-- aceptable: pago recibe pocas escrituras (una por apartamento al mes) y
-- muchísimas lecturas de reportes.
-- ---------------------------------------------------------------------
SELECT  indexrelname                                 AS indice,
        pg_size_pretty(pg_relation_size(indexrelid)) AS tamano
FROM pg_stat_user_indexes
WHERE relname = 'pago_prueba'
ORDER BY indexrelname;

SELECT pg_size_pretty(pg_relation_size('pago_prueba')) AS tamano_tabla;


-- ---------------------------------------------------------------------
-- PASO 6: limpiar la tabla de prueba
-- ---------------------------------------------------------------------
DROP TABLE pago_prueba;


-- ---------------------------------------------------------------------
-- PASO 7: INDICES DEFINITIVOS sobre la tabla real "pago"
-- (esto es lo que queda en la base de datos del proyecto)
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_pago_fecha_pago ON pago USING btree (fecha_pago);
CREATE INDEX IF NOT EXISTS idx_pago_id_cuota   ON pago USING btree (id_cuota);

-- Verificación: lista los índices de la tabla pago
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'pago'
ORDER BY indexname;

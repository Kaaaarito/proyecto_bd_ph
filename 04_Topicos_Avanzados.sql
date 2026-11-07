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


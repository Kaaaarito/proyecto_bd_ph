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
SECURITY DEFINER --para que puedan pagar sin darle permisos sobre la tabla
AS $$
DECLARE
    v_valor_cuota DECIMAL(12,2);
BEGIN
    -- 1. Consultar cuánto vale la cuota realmente
    SELECT valor INTO v_valor_cuota FROM cuota_admin WHERE id_cuota = p_id_cuota;

    -- 2. REGLA ESTRICTA: Si el monto no es EXACTAMENTE la cuota, bloqueamos todo.
    IF p_monto <> v_valor_cuota THEN
        RAISE EXCEPTION 'ERROR: Transacción rechazada. El pago debe ser exactamente de $ %', v_valor_cuota;
    END IF;

    -- 3. Si pasó la validación, insertamos el pago
    INSERT INTO pago (id_apartamento, id_cuota, fecha_pago, monto_pagado, metodo_pago)
    VALUES (p_id_apartamento, p_id_cuota, CURRENT_DATE, p_monto, p_metodo);

END;
$$;

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
        CURRENT_TIMESTAMP, CURRENT_USER, 'Trigger fn_auditar_pago', 'INSERT', 'Pago Completo', 'N/A',
        NEW.id_apartamento, NEW.id_cuota, NEW.id_pago, NEW.monto_pagado, NEW.monto_pagado, 0,
        'Pago exacto procesado exitosamente.'
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
GRANT EXECUTE ON PROCEDURE sp_procesar_pago_admin(INT, INT, DECIMAL, VARCHAR) TO rol_propietario;

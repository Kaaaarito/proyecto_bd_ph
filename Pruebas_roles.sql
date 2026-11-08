-- PRUEBA VIGILANTE  (conexión: vigilante_luis / Vigilante_PH26*)
SELECT placa, marca FROM vehiculo;                      -- exitoso
INSERT INTO ingreso_visita (id_ingreso, id_visitante, id_apartamento, id_trabajador, hora_entrada)
VALUES (41, 1, 1, 9, CURRENT_TIMESTAMP);                -- exitoso: el vigilante registra visitas
SELECT * FROM cuota_admin;                              -- ERROR: permission denied

-- PRUEBA PROPIETARIO  (conexión: prop_apto101 / Prop101_PH26*)
SELECT nombre_zona, capacidad, tarifa_hora FROM zona_comun;   -- exitoso
CALL sp_procesar_pago_admin(1, 1, 150000.00, 'PSE');   -- ERROR: pago incompleto
CALL sp_procesar_pago_admin(1, 1, 185000.00, 'PSE');   -- exitoso
CALL sp_procesar_pago_admin(1, 1, 185000.00, 'PSE');   -- ERROR: la cuota ya fue pagada
SELECT * FROM ingreso_visita;                           -- ERROR: permission denied
INSERT INTO pago (id_pago, id_apartamento, id_cuota, fecha_pago, monto_pagado, metodo_pago)
VALUES (999, 1, 2, CURRENT_DATE, 185000, 'PSE');        -- ERROR: no puede insertar directo, solo con el procedimiento

-- PRUEBA SECRETARIA  (conexión: secretaria_ana / Secretaria_PH26*)
UPDATE residente
SET correo = 'nuevo_correo_2026@correo.com'
WHERE id_residente = 1;                                 -- exitoso
DELETE FROM reserva WHERE id_reserva = 1;               -- ERROR: no tiene DELETE
SELECT * FROM cuota_admin;                              -- ERROR: permission denied
SELECT * FROM vw_estado_financiero ORDER BY cuotas_sin_pagar LIMIT 5;  -- exitoso

-- PRUEBA ADMINISTRADOR  (conexión: admin_pedro / Admin_PH26*)
SELECT * FROM apartamento;
SELECT * FROM cuota_admin;
UPDATE zona_comun SET tarifa_hora = 60000.00 WHERE id_zona = 1;
DELETE FROM reserva WHERE id_reserva = 2;

-- estado financiero de cada apartamento
SELECT * FROM vw_estado_financiero ORDER BY estado_financiero, cuotas_sin_pagar;

-- quién hizo los últimos pagos (el trigger guarda el usuario de la conexión)
SELECT id_auditoria, fecha_hora, usuario_bd, origen, id_apartamento, id_cuota, monto_aplicado
FROM auditoria_pago
ORDER BY id_auditoria DESC
LIMIT 5;
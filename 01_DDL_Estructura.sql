-- Limpieza (orden inverso a las dependencias)
DROP TABLE IF EXISTS auditoria_pago CASCADE;
DROP TABLE IF EXISTS ingreso_visita CASCADE;
DROP TABLE IF EXISTS pago CASCADE;
DROP TABLE IF EXISTS cuota_admin CASCADE;
DROP TABLE IF EXISTS telefono CASCADE;
DROP TABLE IF EXISTS vehiculo CASCADE;
DROP TABLE IF EXISTS parqueadero CASCADE;
DROP TABLE IF EXISTS reserva CASCADE;
DROP TABLE IF EXISTS zona_comun CASCADE;
DROP TABLE IF EXISTS visitante CASCADE;
DROP TABLE IF EXISTS trabajador CASCADE;
DROP TABLE IF EXISTS residente CASCADE;
DROP TABLE IF EXISTS apartamento CASCADE;
DROP TABLE IF EXISTS torre CASCADE;

-- torre
CREATE TABLE torre (
    id_torre      INT         NOT NULL,
    nombre_torre  VARCHAR(30) NOT NULL,
    numero_pisos  INT         NOT NULL,
    CONSTRAINT pk_torre PRIMARY KEY (id_torre),
    CONSTRAINT uq_torre_nombre UNIQUE (nombre_torre),
    CONSTRAINT ck_torre_pisos CHECK (numero_pisos > 0)
);

-- apartamento
CREATE TABLE apartamento (
    id_apartamento   INT           NOT NULL,
    id_torre         INT           NOT NULL,
    numero_apto      VARCHAR(10)   NOT NULL,
    piso             INT           NOT NULL,
    area_m2          DECIMAL(6,2)  NOT NULL,
    num_habitaciones INT           NOT NULL,
    CONSTRAINT pk_apartamento PRIMARY KEY (id_apartamento),
    CONSTRAINT fk_apartamento_torre FOREIGN KEY (id_torre) REFERENCES torre (id_torre),
    CONSTRAINT uq_apartamento_torre_numero UNIQUE (id_torre, numero_apto),
    CONSTRAINT ck_apartamento_piso CHECK (piso > 0),
    CONSTRAINT ck_apartamento_area CHECK (area_m2 > 0),
    CONSTRAINT ck_apartamento_habitaciones CHECK (num_habitaciones >= 1)
);

-- residente
CREATE TABLE residente (
    id_residente     INT          NOT NULL,
    id_apartamento   INT          NOT NULL,
    tipo_documento   VARCHAR(5)   NOT NULL,
    numero_documento VARCHAR(15)  NOT NULL,
    nombres          VARCHAR(60)  NOT NULL,
    apellidos        VARCHAR(60)  NOT NULL,
    fecha_nacimiento DATE         NOT NULL,
    correo           VARCHAR(80)  NOT NULL,
    rol              VARCHAR(20)  NOT NULL,
    estado           BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_residente PRIMARY KEY (id_residente),
    CONSTRAINT fk_residente_apartamento FOREIGN KEY (id_apartamento) REFERENCES apartamento (id_apartamento),
    CONSTRAINT uq_residente_documento UNIQUE (tipo_documento, numero_documento),
    CONSTRAINT uq_residente_correo UNIQUE (correo),
    CONSTRAINT ck_residente_tipo_doc CHECK (tipo_documento IN ('CC', 'CE', 'TI', 'PA')),
    CONSTRAINT ck_residente_rol CHECK (rol IN ('Propietario', 'Arrendatario', 'Familiar')),
    CONSTRAINT ck_residente_nacimiento CHECK (fecha_nacimiento <= CURRENT_DATE)
);

-- trabajador
CREATE TABLE trabajador (
    id_trabajador    INT          NOT NULL,
    tipo_documento   VARCHAR(5)   NOT NULL,
    numero_documento VARCHAR(15)  NOT NULL,
    nombres          VARCHAR(60)  NOT NULL,
    apellidos        VARCHAR(60)  NOT NULL,
    cargo            VARCHAR(30)  NOT NULL,
    correo           VARCHAR(80)  NOT NULL,
    CONSTRAINT pk_trabajador PRIMARY KEY (id_trabajador),
    CONSTRAINT uq_trabajador_documento UNIQUE (tipo_documento, numero_documento),
    CONSTRAINT uq_trabajador_correo UNIQUE (correo),
    CONSTRAINT ck_trabajador_tipo_doc CHECK (tipo_documento IN ('CC', 'CE', 'PA'))
);

-- visitante
CREATE TABLE visitante (
    id_visitante     INT          NOT NULL,
    tipo_documento   VARCHAR(5)   NOT NULL,
    numero_documento VARCHAR(15)  NOT NULL,
    nombre_visitante VARCHAR(80)  NOT NULL,
    CONSTRAINT pk_visitante PRIMARY KEY (id_visitante),
    CONSTRAINT uq_visitante_documento UNIQUE (tipo_documento, numero_documento),
    CONSTRAINT ck_visitante_tipo_doc CHECK (tipo_documento IN ('CC', 'CE', 'TI', 'PA'))
);

-- zona_comun
CREATE TABLE zona_comun (
    id_zona        INT            NOT NULL,
    nombre_zona    VARCHAR(60)    NOT NULL,
    capacidad      INT            NOT NULL,
    tarifa_hora    DECIMAL(10,2)  NOT NULL DEFAULT 0,
    hora_apertura  TIME           NOT NULL,
    hora_cierre    TIME           NOT NULL,
    CONSTRAINT pk_zona_comun PRIMARY KEY (id_zona),
    CONSTRAINT uq_zona_nombre UNIQUE (nombre_zona),
    CONSTRAINT ck_zona_capacidad CHECK (capacidad > 0),
    CONSTRAINT ck_zona_tarifa CHECK (tarifa_hora >= 0),
    CONSTRAINT ck_zona_horario CHECK (hora_cierre > hora_apertura)
);

-- reserva
CREATE TABLE reserva (
    id_reserva     INT          NOT NULL,
    id_residente   INT          NOT NULL,
    id_zona        INT          NOT NULL,
    fecha_reserva  DATE         NOT NULL,
    hora_inicio    TIME         NOT NULL,
    hora_fin       TIME         NOT NULL,
    estado         VARCHAR(15)  NOT NULL DEFAULT 'Pendiente',
    CONSTRAINT pk_reserva PRIMARY KEY (id_reserva),
    CONSTRAINT fk_reserva_residente FOREIGN KEY (id_residente) REFERENCES residente (id_residente),
    CONSTRAINT fk_reserva_zona FOREIGN KEY (id_zona) REFERENCES zona_comun (id_zona),
    CONSTRAINT ck_reserva_horas CHECK (hora_fin > hora_inicio),
    CONSTRAINT ck_reserva_estado CHECK (estado IN ('Pendiente', 'Confirmada', 'Cancelada', 'Finalizada'))
);

-- parqueadero
CREATE TABLE parqueadero (
    id_parqueadero      INT          NOT NULL,
    id_apartamento      INT          NOT NULL,
    numero_parqueadero  VARCHAR(10)  NOT NULL,
    tipo_parqueadero    VARCHAR(15)  NOT NULL,
    CONSTRAINT pk_parqueadero PRIMARY KEY (id_parqueadero),
    CONSTRAINT fk_parqueadero_apartamento FOREIGN KEY (id_apartamento) REFERENCES apartamento (id_apartamento),
    CONSTRAINT uq_parqueadero_numero UNIQUE (numero_parqueadero),
    CONSTRAINT ck_parqueadero_tipo CHECK (tipo_parqueadero IN ('Carro', 'Moto'))
);

-- vehiculo
CREATE TABLE vehiculo (
    id_vehiculo     INT          NOT NULL,
    id_parqueadero  INT          NOT NULL,
    placa           VARCHAR(8)   NOT NULL,
    tipo_vehiculo   VARCHAR(20)  NOT NULL,
    marca           VARCHAR(30)  NOT NULL,
    color           VARCHAR(20)  NOT NULL,
    CONSTRAINT pk_vehiculo PRIMARY KEY (id_vehiculo),
    CONSTRAINT fk_vehiculo_parqueadero FOREIGN KEY (id_parqueadero) REFERENCES parqueadero (id_parqueadero),
    CONSTRAINT uq_vehiculo_placa UNIQUE (placa),
    CONSTRAINT ck_vehiculo_tipo CHECK (tipo_vehiculo IN ('Carro', 'Moto'))
);

-- telefono
-- Cada teléfono pertenece a un residente O a un trabajador (nunca a ambos).
CREATE TABLE telefono (
    id_telefono    INT          NOT NULL,
    id_residente   INT,
    id_trabajador  INT,
    numero         VARCHAR(15)  NOT NULL,
    CONSTRAINT pk_telefono PRIMARY KEY (id_telefono),
    CONSTRAINT fk_telefono_residente FOREIGN KEY (id_residente) REFERENCES residente (id_residente),
    CONSTRAINT fk_telefono_trabajador FOREIGN KEY (id_trabajador) REFERENCES trabajador (id_trabajador),
    CONSTRAINT uq_telefono_numero UNIQUE (numero),
    CONSTRAINT ck_telefono_propietario CHECK (
        (id_residente IS NOT NULL AND id_trabajador IS NULL) OR
        (id_residente IS NULL AND id_trabajador IS NOT NULL)
    )
);

-- cuota_admin
CREATE TABLE cuota_admin (
    id_cuota           INT            NOT NULL,
    periodo            CHAR(7)        NOT NULL,
    valor              DECIMAL(12,2)  NOT NULL,
    fecha_vencimiento  DATE           NOT NULL,
    CONSTRAINT pk_cuota_admin PRIMARY KEY (id_cuota),
    CONSTRAINT uq_cuota_periodo UNIQUE (periodo),
    CONSTRAINT ck_cuota_periodo CHECK (periodo ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
    CONSTRAINT ck_cuota_valor CHECK (valor > 0)
);

-- pago
CREATE TABLE pago (
    id_pago         INT            NOT NULL,
    id_apartamento  INT            NOT NULL,
    id_cuota        INT            NOT NULL,
    fecha_pago      DATE           NOT NULL,
    monto_pagado    DECIMAL(12,2)  NOT NULL,
    metodo_pago     VARCHAR(20)    NOT NULL,
    CONSTRAINT pk_pago PRIMARY KEY (id_pago),
    CONSTRAINT fk_pago_apartamento FOREIGN KEY (id_apartamento) REFERENCES apartamento (id_apartamento),
    CONSTRAINT fk_pago_cuota FOREIGN KEY (id_cuota) REFERENCES cuota_admin (id_cuota),
    CONSTRAINT uq_pago_apartamento_cuota UNIQUE (id_apartamento, id_cuota),
    CONSTRAINT ck_pago_monto CHECK (monto_pagado > 0),
    CONSTRAINT ck_pago_metodo CHECK (metodo_pago IN ('Efectivo', 'Transferencia', 'PSE', 'Tarjeta débito', 'Tarjeta crédito'))
);

-- ingreso_visita
CREATE TABLE ingreso_visita (
    id_ingreso      INT        NOT NULL,
    id_visitante    INT        NOT NULL,
    id_apartamento  INT        NOT NULL,
    id_trabajador   INT        NOT NULL,
    hora_entrada    TIMESTAMP  NOT NULL,
    hora_salida     TIMESTAMP,
    CONSTRAINT pk_ingreso_visita PRIMARY KEY (id_ingreso),
    CONSTRAINT fk_ingreso_visitante FOREIGN KEY (id_visitante) REFERENCES visitante (id_visitante),
    CONSTRAINT fk_ingreso_apartamento FOREIGN KEY (id_apartamento) REFERENCES apartamento (id_apartamento),
    CONSTRAINT fk_ingreso_trabajador FOREIGN KEY (id_trabajador) REFERENCES trabajador (id_trabajador),
    CONSTRAINT ck_ingreso_horas CHECK (hora_salida IS NULL OR hora_salida > hora_entrada)
);

-- auditoria_pago
-- intentos fallidos donde el pago nunca llegó a crearse.
CREATE TABLE auditoria_pago (
    id_auditoria      SERIAL,
    fecha_hora        TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_bd        VARCHAR(60)    NOT NULL,
    origen            VARCHAR(15)    NOT NULL,
    operacion         VARCHAR(10)    NOT NULL,
    resultado         VARCHAR(20)    NOT NULL,
    codigo_error      VARCHAR(30),
    id_apartamento    INT,
    id_cuota          INT,
    id_pago           INT,
    monto_intentado   DECIMAL(12,2),
    monto_aplicado    DECIMAL(12,2),
    saldo_pendiente   DECIMAL(12,2),
    detalle           TEXT,
    CONSTRAINT pk_auditoria_pago PRIMARY KEY (id_auditoria),
    CONSTRAINT fk_auditoria_apartamento FOREIGN KEY (id_apartamento) REFERENCES apartamento (id_apartamento),
    CONSTRAINT fk_auditoria_cuota FOREIGN KEY (id_cuota) REFERENCES cuota_admin (id_cuota),
    CONSTRAINT ck_auditoria_operacion CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE')),
    CONSTRAINT ck_auditoria_resultado CHECK (resultado IN ('EXITOSO', 'FALLIDO'))
);

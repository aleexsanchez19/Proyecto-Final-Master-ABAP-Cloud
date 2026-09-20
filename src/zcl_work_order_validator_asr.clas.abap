" Clase que contiene validaciones de las órdenes de trabajo
CLASS zcl_work_order_validator_asr DEFINITION PUBLIC FINAL CREATE PRIVATE.
  PUBLIC SECTION.

    " Devuelve instancia de la clase
    CLASS-METHODS get_instance RETURNING VALUE(ro_instance) TYPE REF TO zcl_work_order_validator_asr.

    " Validación para crear orden (cliente existe, técnico existe y prioridad es válida)
    METHODS validate_create_order
      IMPORTING iv_customer_id   TYPE zde_customer_id_asr
                iv_technician_id TYPE zde_technician_id_asr
                iv_priority      TYPE zde_priority_asr
      RETURNING VALUE(rv_valid)  TYPE abap_bool.

    " Validación para actualizar orden (existe, estado editable y nuevos valores válidos)
    METHODS validate_update_order
      IMPORTING iv_work_order_id TYPE zde_work_order_id_asr
                iv_status        TYPE zde_status_asr
                iv_priority      TYPE zde_priority_asr
      RETURNING VALUE(rv_valid)  TYPE abap_bool.

    " Validación para borrar orden (existe, estado pendiente y no tiene historial de cambios)
    METHODS validate_delete_order
      IMPORTING iv_work_order_id TYPE zde_work_order_id_asr
      RETURNING VALUE(rv_valid)  TYPE abap_bool.

    " Valida estado y prioridad existe en tabla de configuración
    METHODS validate_status_and_priority
      IMPORTING iv_status       TYPE zde_status_asr
                iv_priority     TYPE zde_priority_asr
      RETURNING VALUE(rv_valid) TYPE abap_bool.

  PRIVATE SECTION.

    " Instancia única de la clase
    CLASS-DATA go_instance TYPE REF TO zcl_work_order_validator_asr.

    " Constante estado pendiente
    CONSTANTS c_status_pending TYPE zde_status_asr VALUE 'PE'.

    " Métodos auxiliares
    METHODS check_customer_exists   IMPORTING iv_id TYPE zde_customer_id_asr   RETURNING VALUE(rv_exists) TYPE abap_bool.
    METHODS check_technician_exists IMPORTING iv_id TYPE zde_technician_id_asr RETURNING VALUE(rv_exists) TYPE abap_bool.
    METHODS check_order_exists      IMPORTING iv_id TYPE zde_work_order_id_asr RETURNING VALUE(rv_exists) TYPE abap_bool.
    METHODS check_order_history     IMPORTING iv_id TYPE zde_work_order_id_asr RETURNING VALUE(rv_exists) TYPE abap_bool.
    METHODS get_current_status      IMPORTING iv_id TYPE zde_work_order_id_asr RETURNING VALUE(rv_status) TYPE zde_status_asr.
ENDCLASS.

CLASS zcl_work_order_validator_asr IMPLEMENTATION.
  METHOD get_instance.
    IF go_instance IS NOT BOUND.
      go_instance = NEW #( ).
    ENDIF.
    ro_instance = go_instance.
  ENDMETHOD.

  METHOD validate_create_order.
    rv_valid = xsdbool( iv_customer_id   IS NOT INITIAL AND check_customer_exists( iv_customer_id ) = abap_true
                    AND iv_technician_id IS NOT INITIAL AND check_technician_exists( iv_technician_id ) = abap_true
                    AND validate_status_and_priority( iv_status = c_status_pending iv_priority = iv_priority ) = abap_true ).
  ENDMETHOD.

  METHOD validate_update_order.
    IF check_order_exists( iv_work_order_id ) = abap_false
       OR get_current_status( iv_work_order_id ) <> c_status_pending.
      RETURN.
    ENDIF.
    rv_valid = validate_status_and_priority( iv_status = iv_status iv_priority = iv_priority ).
  ENDMETHOD.

  METHOD validate_delete_order.
    rv_valid = xsdbool( check_order_exists( iv_work_order_id ) = abap_true
                    AND get_current_status( iv_work_order_id ) = c_status_pending
                    AND check_order_history( iv_work_order_id ) = abap_false ).
  ENDMETHOD.

  METHOD validate_status_and_priority.
    SELECT SINGLE @abap_true FROM ztc_status   WHERE status_code   = @iv_status   INTO @DATA(lv_status_ok).
    SELECT SINGLE @abap_true FROM ztc_priority WHERE priority_code = @iv_priority INTO @DATA(lv_prio_ok).
    rv_valid = xsdbool( lv_status_ok = abap_true AND lv_prio_ok = abap_true ).
  ENDMETHOD.

  METHOD check_customer_exists.
    SELECT SINGLE @abap_true FROM ztt_customer WHERE customer_id = @iv_id INTO @rv_exists.
  ENDMETHOD.

  METHOD check_technician_exists.
    SELECT SINGLE @abap_true FROM ztt_technician WHERE technician_id = @iv_id INTO @rv_exists.
  ENDMETHOD.

  METHOD check_order_exists.
    SELECT SINGLE @abap_true FROM ztt_work_order WHERE work_order_id = @iv_id INTO @rv_exists.
  ENDMETHOD.

  METHOD check_order_history.
    SELECT SINGLE @abap_true FROM ztt_work_order_h WHERE work_order_id = @iv_id INTO @rv_exists.
  ENDMETHOD.

  METHOD get_current_status.
    SELECT SINGLE status FROM ztt_work_order WHERE work_order_id = @iv_id INTO @rv_status.
  ENDMETHOD.
ENDCLASS.

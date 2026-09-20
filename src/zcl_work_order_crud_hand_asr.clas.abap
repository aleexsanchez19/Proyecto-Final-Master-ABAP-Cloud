CLASS zcl_work_order_crud_hand_asr DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      tt_work_orders TYPE STANDARD TABLE OF ztt_work_order WITH EMPTY KEY,
      tt_r_date      TYPE RANGE OF d,
      tt_r_status    TYPE RANGE OF zde_status_asr,
      tt_r_customer  TYPE RANGE OF zde_customer_id_asr.

    " Constructor: obtiene la instancia del validador
    METHODS constructor.

    " Crea una orden de trabajo en estado Pendiente (PE)
    METHODS create_work_order
      IMPORTING iv_customer_id   TYPE zde_customer_id_asr
                iv_technician_id TYPE zde_technician_id_asr
                iv_priority      TYPE zde_priority_asr
                iv_description   TYPE zde_description_order_asr
      EXPORTING ev_work_order_id TYPE zde_work_order_id_asr
                ev_message       TYPE string
      RETURNING VALUE(rv_ok)     TYPE abap_bool.

    " Lee órdenes de trabajo con filtros opcionales.
    METHODS read_work_order
      IMPORTING iv_work_order_id TYPE zde_work_order_id_asr OPTIONAL
                it_r_date        TYPE tt_r_date OPTIONAL
                it_r_status      TYPE tt_r_status OPTIONAL
                it_r_customer    TYPE tt_r_customer OPTIONAL
      EXPORTING ev_message       TYPE string
      RETURNING VALUE(rt_orders) TYPE tt_work_orders.

    " Actualiza estado y prioridad de una orden pendiente,
    " con bloqueo y registro en el historial
    METHODS update_work_order
      IMPORTING iv_work_order_id TYPE zde_work_order_id_asr
                iv_status        TYPE zde_status_asr
                iv_priority      TYPE zde_priority_asr
      EXPORTING ev_message       TYPE string
      RETURNING VALUE(rv_ok)     TYPE abap_bool.

    " Borra una orden pendiente y sin historial, con bloqueo
    METHODS delete_work_order
      IMPORTING iv_work_order_id TYPE zde_work_order_id_asr
      EXPORTING ev_message       TYPE string
      RETURNING VALUE(rv_ok)     TYPE abap_bool.

  PRIVATE SECTION.
    TYPES tv_actvt TYPE c LENGTH 2.

    CONSTANTS:
      gc_auth_object   TYPE c LENGTH 10 VALUE 'ZAO_WO',
      gc_lock_object   TYPE c LENGTH 16 VALUE 'EZ_WORK_ORDER',
      gc_status_pending TYPE zde_status_asr VALUE 'PE',
      BEGIN OF gc_actvt,
        create  TYPE tv_actvt VALUE '01',
        change  TYPE tv_actvt VALUE '02',
        display TYPE tv_actvt VALUE '03',
        delete  TYPE tv_actvt VALUE '06',
      END OF gc_actvt.

    DATA mo_validator TYPE REF TO zcl_work_order_validator_asr.
    DATA mo_lock      TYPE REF TO if_abap_lock_object.

    " Comprueba la autorización ZAO_WO para una actividad
    METHODS check_authority
      IMPORTING iv_actvt     TYPE tv_actvt
      RETURNING VALUE(rv_ok) TYPE abap_bool.

    " Bloquea una orden
    METHODS lock_order
      IMPORTING iv_work_order_id TYPE zde_work_order_id_asr
      EXPORTING ev_message       TYPE string
      RETURNING VALUE(rv_ok)     TYPE abap_bool.

    " Desbloquea una orden
    METHODS unlock_order
      IMPORTING iv_work_order_id TYPE zde_work_order_id_asr.

    " Lógica de actualización
    METHODS execute_update
      IMPORTING iv_work_order_id TYPE zde_work_order_id_asr
                iv_status        TYPE zde_status_asr
                iv_priority      TYPE zde_priority_asr
      EXPORTING ev_message       TYPE string
      RETURNING VALUE(rv_ok)     TYPE abap_bool.

    " Lógica de borrado
    METHODS execute_delete
      IMPORTING iv_work_order_id TYPE zde_work_order_id_asr
      EXPORTING ev_message       TYPE string
      RETURNING VALUE(rv_ok)     TYPE abap_bool.

ENDCLASS.


CLASS zcl_work_order_crud_hand_asr IMPLEMENTATION.

  METHOD constructor.
    mo_validator = zcl_work_order_validator_asr=>get_instance( ).
  ENDMETHOD.


  METHOD create_work_order.
    CLEAR: ev_work_order_id, ev_message.

    " 1. Autorización
    IF check_authority( gc_actvt-create ) = abap_false.
      ev_message = 'Sin autorización para crear órdenes de trabajo'.
      RETURN.
    ENDIF.

    " 2. Validaciones de negocio
    IF mo_validator->validate_create_order( iv_customer_id   = iv_customer_id
                                            iv_technician_id = iv_technician_id
                                            iv_priority      = iv_priority ) = abap_false.
      ev_message = 'Datos no válidos: revise cliente, técnico y prioridad'.
      RETURN.
    ENDIF.

    " 3. Siguiente ID de orden
    SELECT MAX( work_order_id ) FROM ztt_work_order INTO @DATA(lv_max_id).

    DATA(ls_order) = VALUE ztt_work_order(
        work_order_id = lv_max_id + 1
        customer_id   = iv_customer_id
        technician_id = iv_technician_id
        creation_date = cl_abap_context_info=>get_system_date( )
        status        = gc_status_pending
        priority      = iv_priority
        description   = iv_description ).

    " 4. Inserta en tabla
    INSERT ztt_work_order FROM @ls_order.
    IF sy-subrc <> 0.
      ev_message = 'Error al grabar la orden de trabajo'.
      RETURN.
    ENDIF.
    COMMIT WORK.

    ev_work_order_id = ls_order-work_order_id.
    ev_message       = |Orden { ls_order-work_order_id ALPHA = OUT } creada correctamente|.
    rv_ok            = abap_true.
  ENDMETHOD.


  METHOD read_work_order.
    DATA lt_r_order TYPE RANGE OF zde_work_order_id_asr.

    CLEAR ev_message.

    " 1. Autorización
    IF check_authority( gc_actvt-display ) = abap_false.
      ev_message = 'Sin autorización para visualizar órdenes de trabajo'.
      RETURN.
    ENDIF.

    " 2. Filtro por orden concreta (si se informa)
    IF iv_work_order_id IS NOT INITIAL.
      lt_r_order = VALUE #( ( sign = 'I' option = 'EQ' low = iv_work_order_id ) ).
    ENDIF.

    " 3. Lectura dinámica: los rangos vacíos no filtran
    SELECT * FROM ztt_work_order
      WHERE work_order_id IN @lt_r_order
        AND creation_date IN @it_r_date
        AND status        IN @it_r_status
        AND customer_id   IN @it_r_customer
      ORDER BY work_order_id
      INTO TABLE @rt_orders.

    IF rt_orders IS INITIAL.
      ev_message = 'No se han encontrado órdenes con los filtros indicados'.
    ELSE.
      ev_message = |{ lines( rt_orders ) } orden(es) encontrada(s)|.
    ENDIF.
  ENDMETHOD.


  METHOD update_work_order.
    CLEAR ev_message.

    " 1. Autorización
    IF check_authority( gc_actvt-change ) = abap_false.
      ev_message = 'Sin autorización para modificar órdenes de trabajo'.
      RETURN.
    ENDIF.

    " 2. Bloqueo (control de concurrencia)
    IF lock_order( EXPORTING iv_work_order_id = iv_work_order_id
                   IMPORTING ev_message       = ev_message ) = abap_false.
      RETURN.
    ENDIF.

    " 3. Validación y actualización con la orden bloqueada
    rv_ok = execute_update( EXPORTING iv_work_order_id = iv_work_order_id
                                      iv_status        = iv_status
                                      iv_priority      = iv_priority
                            IMPORTING ev_message       = ev_message ).

    " 4. Desbloqueo (siempre)
    unlock_order( iv_work_order_id ).
  ENDMETHOD.


  METHOD delete_work_order.
    CLEAR ev_message.

    " 1. Autorización
    IF check_authority( gc_actvt-delete ) = abap_false.
      ev_message = 'Sin autorización para borrar órdenes de trabajo'.
      RETURN.
    ENDIF.

    " 2. Bloqueo (control de concurrencia)
    IF lock_order( EXPORTING iv_work_order_id = iv_work_order_id
                   IMPORTING ev_message       = ev_message ) = abap_false.
      RETURN.
    ENDIF.

    " 3. Validación y borrado con la orden bloqueada
    rv_ok = execute_delete( EXPORTING iv_work_order_id = iv_work_order_id
                            IMPORTING ev_message       = ev_message ).

    " 4. Desbloqueo (siempre)
    unlock_order( iv_work_order_id ).
  ENDMETHOD.


  METHOD execute_update.
    CLEAR ev_message.

    " Se valida DESPUÉS de bloquear, para que nadie cambie la orden entre medias
    IF mo_validator->validate_update_order( iv_work_order_id = iv_work_order_id
                                            iv_status        = iv_status
                                            iv_priority      = iv_priority ) = abap_false.
      ev_message = |Orden { iv_work_order_id ALPHA = OUT }: no existe, no está pendiente | &&
                   |o los valores de estado/prioridad no son válidos|.
      RETURN.
    ENDIF.

    " Valores actuales, para el historial
    SELECT SINGLE status, priority
      FROM ztt_work_order
      WHERE work_order_id = @iv_work_order_id
      INTO @DATA(ls_old).

    IF ls_old-status = iv_status AND ls_old-priority = iv_priority.
      ev_message = 'No hay cambios que guardar'.
      RETURN.
    ENDIF.

    " Actualización condicional de estado y prioridad
    UPDATE ztt_work_order
      SET status   = @iv_status,
          priority = @iv_priority
      WHERE work_order_id = @iv_work_order_id.
    IF sy-subrc <> 0.
      ev_message = 'Error al actualizar la orden de trabajo'.
      RETURN.
    ENDIF.

    " Registro en el historial
    SELECT MAX( history_id ) FROM ztt_work_order_h INTO @DATA(lv_max_hist).

    DATA(ls_hist) = VALUE ztt_work_order_h(
        history_id         = lv_max_hist + 1
        work_order_id      = iv_work_order_id
        modification_date  = cl_abap_context_info=>get_system_date( )
        change_description = |Estado { ls_old-status }->{ iv_status }, | &&
                             |Prioridad { ls_old-priority }->{ iv_priority }| ).

    INSERT ztt_work_order_h FROM @ls_hist.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      ev_message = 'Error al grabar el historial; cambios deshechos'.
      RETURN.
    ENDIF.

    COMMIT WORK.
    ev_message = |Orden { iv_work_order_id ALPHA = OUT } actualizada correctamente|.
    rv_ok      = abap_true.
  ENDMETHOD.


  METHOD execute_delete.
    CLEAR ev_message.

    IF mo_validator->validate_delete_order( iv_work_order_id ) = abap_false.
      ev_message = |Orden { iv_work_order_id ALPHA = OUT }: no existe, no está pendiente | &&
                   |o tiene historial de cambios|.
      RETURN.
    ENDIF.

    DELETE FROM ztt_work_order WHERE work_order_id = @iv_work_order_id.
    IF sy-subrc <> 0.
      ev_message = 'Error al borrar la orden de trabajo'.
      RETURN.
    ENDIF.

    COMMIT WORK.
    ev_message = |Orden { iv_work_order_id ALPHA = OUT } borrada correctamente|.
    rv_ok      = abap_true.
  ENDMETHOD.


  METHOD check_authority.
    AUTHORITY-CHECK OBJECT gc_auth_object
      ID 'ACTVT' FIELD iv_actvt.
    rv_ok = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.


  METHOD lock_order.
    " Copia local: el lock recibe una referencia al valor
    DATA(lv_id) = iv_work_order_id.
    CLEAR ev_message.

    TRY.
        mo_lock = cl_abap_lock_object_factory=>get_instance( iv_name = CONV #( gc_lock_object ) ).
        mo_lock->enqueue( it_parameter = VALUE if_abap_lock_object=>tt_parameter(
                                           ( name = 'WORK_ORDER_ID' value = REF #( lv_id ) ) ) ).
        rv_ok = abap_true.
      CATCH cx_abap_foreign_lock.
        ev_message = |La orden { iv_work_order_id ALPHA = OUT } está bloqueada por otro usuario|.
      CATCH cx_abap_lock_failure INTO DATA(lx_lock).
        ev_message = lx_lock->get_text( ).
    ENDTRY.
  ENDMETHOD.


  METHOD unlock_order.
    DATA(lv_id) = iv_work_order_id.

    IF mo_lock IS NOT BOUND.
      RETURN.
    ENDIF.

    TRY.
        mo_lock->dequeue( it_parameter = VALUE if_abap_lock_object=>tt_parameter(
                                           ( name = 'WORK_ORDER_ID' value = REF #( lv_id ) ) ) ).
      CATCH cx_abap_lock_failure ##NO_HANDLER.
        " El bloqueo puede haberse liberado ya con el COMMIT: no es un error
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

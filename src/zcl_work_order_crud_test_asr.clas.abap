CLASS zcl_work_order_crud_test_asr DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    CONSTANTS:
      gc_customer   TYPE zde_customer_id_asr   VALUE 'C0000001',
      gc_technician TYPE zde_technician_id_asr VALUE 'T0000001'.

    DATA mo_crud TYPE REF TO zcl_work_order_crud_hand_asr.
    DATA mo_out  TYPE REF TO if_oo_adt_classrun_out.

    " Carga estados, prioridades, cliente y técnico de ejemplo
    METHODS setup_master_data.

    " Crea una orden de apoyo y devuelve su ID
    METHODS create_helper_order
      IMPORTING iv_description   TYPE zde_description_order_asr
      RETURNING VALUE(rv_id)     TYPE zde_work_order_id_asr.

    METHODS test_create_work_order.
    METHODS test_read_work_order.
    METHODS test_update_work_order.
    METHODS test_delete_work_order.

ENDCLASS.


CLASS zcl_work_order_crud_test_asr IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    mo_out  = out.
    mo_crud = NEW #( ).

    setup_master_data( ).

    test_create_work_order( ).
    test_read_work_order( ).
    test_update_work_order( ).
    test_delete_work_order( ).

    mo_out->write( '===== FIN DE LAS PRUEBAS =====' ).
  ENDMETHOD.


  METHOD setup_master_data.
    " Estados y prioridades
    MODIFY ztc_status FROM TABLE @( VALUE #(
        ( status_code = 'PE' status_description = 'Pending' )
        ( status_code = 'CO' status_description = 'Completed' ) ) ).

    MODIFY ztc_priority FROM TABLE @( VALUE #(
        ( priority_code = 'A' priority_descp = 'High' )
        ( priority_code = 'B' priority_descp = 'Low' ) ) ).

    " Cliente y técnico de ejemplo
    MODIFY ztt_customer FROM @( VALUE #(
        customer_id = gc_customer
        name        = 'Cliente Demo S.L.'
        address     = 'Calle Mayor 1, Granada'
        phone       = '958000000' ) ).

    MODIFY ztt_technician FROM @( VALUE #(
        technician_id = gc_technician
        name          = `Técnico Demo`
        speciality     = 'Electricidad' ) ).

    COMMIT WORK.
    mo_out->write( 'Datos maestros cargados' ).
  ENDMETHOD.


  METHOD create_helper_order.
    DATA lv_msg TYPE string.

    mo_crud->create_work_order( EXPORTING iv_customer_id   = gc_customer
                                          iv_technician_id = gc_technician
                                          iv_priority      = 'A'
                                          iv_description   = iv_description
                                IMPORTING ev_work_order_id = rv_id
                                          ev_message       = lv_msg ).
  ENDMETHOD.


  METHOD test_create_work_order.
    DATA: lv_id  TYPE zde_work_order_id_asr,
          lv_msg TYPE string.

    mo_out->write( '===== TEST CREATE =====' ).

    " Caso 1: datos correctos -> debe crearse
    mo_crud->create_work_order( EXPORTING iv_customer_id   = gc_customer
                                          iv_technician_id = gc_technician
                                          iv_priority      = 'A'
                                          iv_description   = 'Revisión cuadro eléctrico'
                                IMPORTING ev_work_order_id = lv_id
                                          ev_message       = lv_msg ).
    mo_out->write( |[OK esperado] { lv_msg }| ).

    " Caso 2: técnico inexistente -> debe fallar
    mo_crud->create_work_order( EXPORTING iv_customer_id   = gc_customer
                                          iv_technician_id = 'NOEXISTE'
                                          iv_priority      = 'A'
                                          iv_description   = 'Debe fallar: técnico'
                                IMPORTING ev_message       = lv_msg ).
    mo_out->write( |[Error esperado] { lv_msg }| ).

    " Caso 3: prioridad no válida -> debe fallar
    mo_crud->create_work_order( EXPORTING iv_customer_id   = gc_customer
                                          iv_technician_id = gc_technician
                                          iv_priority      = 'Z'
                                          iv_description   = 'Debe fallar: prioridad'
                                IMPORTING ev_message       = lv_msg ).
    mo_out->write( |[Error esperado] { lv_msg }| ).
  ENDMETHOD.


  METHOD test_read_work_order.
    DATA lv_msg TYPE string.

    mo_out->write( '===== TEST READ =====' ).

    " Caso 1: todas las órdenes pendientes
    DATA(lt_pending) = mo_crud->read_work_order(
        EXPORTING it_r_status = VALUE #( ( sign = 'I' option = 'EQ' low = 'PE' ) )
        IMPORTING ev_message  = lv_msg ).
    mo_out->write( |Filtro estado PE: { lv_msg }| ).
    mo_out->write( data = lt_pending name = 'Órdenes pendientes' ).

    " Caso 2: órdenes del cliente creadas hoy
    DATA(lv_today) = cl_abap_context_info=>get_system_date( ).
    DATA(lt_customer) = mo_crud->read_work_order(
        EXPORTING it_r_customer = VALUE #( ( sign = 'I' option = 'EQ' low = gc_customer ) )
                  it_r_date     = VALUE #( ( sign = 'I' option = 'EQ' low = lv_today ) )
        IMPORTING ev_message    = lv_msg ).
    mo_out->write( |Filtro cliente + fecha de hoy: { lv_msg }| ).

    " Caso 3: orden inexistente
    mo_crud->read_work_order( EXPORTING iv_work_order_id = '9999999999'
                              IMPORTING ev_message       = lv_msg ).
    mo_out->write( |[Sin resultados esperado] { lv_msg }| ).
  ENDMETHOD.


  METHOD test_update_work_order.
    DATA lv_msg TYPE string.

    mo_out->write( '===== TEST UPDATE =====' ).

    DATA(lv_id) = create_helper_order( 'Orden para test de update' ).

    " Caso 1: cambiar prioridad de una orden pendiente -> OK (genera historial)
    mo_crud->update_work_order( EXPORTING iv_work_order_id = lv_id
                                          iv_status        = 'PE'
                                          iv_priority      = 'B'
                                IMPORTING ev_message       = lv_msg ).
    mo_out->write( |[OK esperado] { lv_msg }| ).

    " Caso 2: completar la orden -> OK
    mo_crud->update_work_order( EXPORTING iv_work_order_id = lv_id
                                          iv_status        = 'CO'
                                          iv_priority      = 'B'
                                IMPORTING ev_message       = lv_msg ).
    mo_out->write( |[OK esperado] { lv_msg }| ).

    " Caso 3: modificar una orden completada -> debe fallar
    mo_crud->update_work_order( EXPORTING iv_work_order_id = lv_id
                                          iv_status        = 'PE'
                                          iv_priority      = 'A'
                                IMPORTING ev_message       = lv_msg ).
    mo_out->write( |[Error esperado] { lv_msg }| ).

    " Caso 4: orden inexistente -> debe fallar
    mo_crud->update_work_order( EXPORTING iv_work_order_id = '9999999999'
                                          iv_status        = 'PE'
                                          iv_priority      = 'A'
                                IMPORTING ev_message       = lv_msg ).
    mo_out->write( |[Error esperado] { lv_msg }| ).

    " Historial generado
    SELECT * FROM ztt_work_order_h
      WHERE work_order_id = @lv_id
      INTO TABLE @DATA(lt_hist).
    mo_out->write( data = lt_hist name = 'Historial de la orden' ).
  ENDMETHOD.


  METHOD test_delete_work_order.
    DATA lv_msg TYPE string.

    mo_out->write( '===== TEST DELETE =====' ).

    " Caso 1: orden pendiente sin historial -> se borra
    DATA(lv_id_ok) = create_helper_order( 'Orden para test de delete' ).
    mo_crud->delete_work_order( EXPORTING iv_work_order_id = lv_id_ok
                                IMPORTING ev_message       = lv_msg ).
    mo_out->write( |[OK esperado] { lv_msg }| ).

    " Caso 2: orden pendiente CON historial -> debe fallar
    DATA(lv_id_hist) = create_helper_order( 'Orden con historial' ).
    mo_crud->update_work_order( EXPORTING iv_work_order_id = lv_id_hist
                                          iv_status        = 'PE'
                                          iv_priority      = 'B'
                                IMPORTING ev_message       = lv_msg ).
    mo_crud->delete_work_order( EXPORTING iv_work_order_id = lv_id_hist
                                IMPORTING ev_message       = lv_msg ).
    mo_out->write( |[Error esperado] { lv_msg }| ).

    " Caso 3: orden inexistente -> debe fallar
    mo_crud->delete_work_order( EXPORTING iv_work_order_id = '9999999999'
                                IMPORTING ev_message       = lv_msg ).
    mo_out->write( |[Error esperado] { lv_msg }| ).
  ENDMETHOD.

ENDCLASS.

/*
 * Copyright (c) MagicRouting
 * Author: Jesús Bocanegra, David Barranco, Alberto Flores, Adrian Marcelo y Enrique Gil
 * Date: 14/05/2016
 * Version: 1.2
 * Published under the terms of the GNU General Public License (GPLv2).
 */

#define AODV_DEBUG  1

module AODV_M {
  provides {
    interface SplitControl;
    interface AMSend[am_id_t id];
    interface Receive[uint8_t id];
  }
  
  uses {
    interface SplitControl as AMControl;
    interface Timer<TMilli> as AODVTimer;
    interface Timer<TMilli> as RREQTimer;
    interface Leds;
    interface Random;
    interface AMPacket;
    interface Packet;
    interface AMSend as SendRREQ;
    interface AMSend as SendRREP;
    interface AMSend as SendRERR;
    interface Receive as ReceiveRREQ;
    interface Receive as ReceiveRREP;
    interface Receive as ReceiveRERR;
    interface AMSend as SubSend;
    interface Receive as SubReceive;
    interface PacketAcknowledgements;
  }
}

implementation {
  
  message_t rreq_msg_;
  message_t rrep_msg_;
  message_t rerr_msg_;
  message_t aodv_msg_;
  message_t app_msg_;
  
  message_t* p_rreq_msg_;
  message_t* p_rrep_msg_;
  message_t* p_rerr_msg_;
  message_t* p_aodv_msg_;
  message_t* p_app_msg_;
  
  uint8_t rreq_seq_ = 0;
  
  bool send_pending_    = FALSE;
  bool rreq_pending_    = FALSE;
  bool rrep_pending_    = FALSE;
  bool rerr_pending_    = FALSE;
  bool msg_pending_ = FALSE;
  
  uint8_t rreq_retries_    = AODV_RREQ_RETRIES;
  uint8_t rrep_retries_    = AODV_RREP_RETRIES;
  uint8_t rerr_retries_    = AODV_RERR_RETRIES;
  uint8_t msg_retries_     = AODV_MSG_RETRIES;
  
  AODV_ROUTE_TABLE route_table_[AODV_ROUTE_TABLE_SIZE];
  AODV_RREQ_CACHE rreq_cache_[AODV_RREQ_CACHE_SIZE];
  
  bool sendRREQ( am_addr_t dest, bool forward );
  task void resendRREQ();
  
  bool sendRREP( am_addr_t dest, bool forward );
  task void resendRREP();
  
  bool sendRERR( am_addr_t dest, am_addr_t src, bool forward );
  task void resendRERR();
  
  error_t forwardMSG( message_t* msg, am_addr_t nextHop, uint8_t len );
  void resendMSG();
  
  uint8_t get_rreq_cache_index( am_addr_t src, am_addr_t dest );
  bool is_rreq_cached( aodv_rreq_hdr* msg );
  bool add_rreq_cache( uint8_t seq, am_addr_t dest, am_addr_t src, uint8_t hop );
  void del_rreq_cache( uint8_t id );
  task void update_rreq_cache();
  
  uint8_t get_route_table_index( am_addr_t dest );
  bool add_route_table( uint8_t seq, am_addr_t dest, am_addr_t nexthop, uint8_t hop );
  void del_route_table( am_addr_t dest );
  am_addr_t get_next_hop( am_addr_t dest );
  
#ifdef AODV_DEBUG
  void print_route_table();
  void print_rreq_cache();
#endif
  

  //--------------------------------------------------------------------------------------------------------------------------------
  //  SplitControl.start: Comienzo del programa, llena las tablas con los valores por defecto e inicia el modulo de radio 
  //--------------------------------------------------------------------------------------------------------------------------------
  command error_t SplitControl.start() {
    int i;
    
    p_rreq_msg_     = &rreq_msg_;
    p_rrep_msg_     = &rrep_msg_;
    p_rerr_msg_     = &rerr_msg_;
    p_aodv_msg_     = &aodv_msg_;
    p_app_msg_      = &app_msg_;
    
    for(i = 0; i< AODV_ROUTE_TABLE_SIZE; i++) {
      route_table_[i].seq  = 0;
      route_table_[i].dest = INVALID_NODE_ID;
      route_table_[i].next = INVALID_NODE_ID;
      route_table_[i].hop  = 0;
    }
    
    for(i = 0; i< AODV_RREQ_CACHE_SIZE; i++) {
      rreq_cache_[i].seq  = 0;
      rreq_cache_[i].dest = INVALID_NODE_ID;
      rreq_cache_[i].src  = INVALID_NODE_ID;
      rreq_cache_[i].hop  = 0;
    }
    
    call AMControl.start();
    
    return SUCCESS;
  }
  
  //--------------------------------------------------------------------------------------------------------------------------------
  //  SplitControl.stop: Funcion que apaga el módulo de radio 
  //--------------------------------------------------------------------------------------------------------------------------------
  command error_t SplitControl.stop() {
    call AMControl.stop();
    return SUCCESS;
  }
  
  //--------------------------------------------------------------------------------------------------------------------------------
  //  AMControl.startDone: Función que inicializa el modulo de radio y le añade el timer para el envio.
  //--------------------------------------------------------------------------------------------------------------------------------
  event void AMControl.startDone( error_t e ) {
    if ( e == SUCCESS ) {
      call AODVTimer.startPeriodic( AODV_DEFAULT_PERIOD );
      signal SplitControl.startDone(e);
    } else {
      call AMControl.start();
    }
  }
  
  //--------------------------------------------------------------------------------------------------------------------------------
  //  AMControl.stopDone: "FALTA POR COMENTAR"
  //--------------------------------------------------------------------------------------------------------------------------------
  event void AMControl.stopDone(error_t e){
    call AODVTimer.stop();
    signal SplitControl.stopDone(e);
  }
  
  //--------------------------------------------------------------------------------------------------------------------------------
  //  sendRREQ: Metodo cuya finalidad es enviar un mensaje de difusion para encontrar el camino hacia el destino.
  //--------------------------------------------------------------------------------------------------------------------------------
  bool sendRREQ( am_addr_t dest, bool forward ) {                         // Parametros de entrada -> dirección de destino (deberiamos cambiarlo por in INT) 
    aodv_rreq_hdr* aodv_hdr = (aodv_rreq_hdr*)(p_rreq_msg_->data);        // Se crea el paquete a enviar
    
    //printf( "%s\t AODV: sendRREQ() dest: %d\n", "", dest);
    
    if( rreq_pending_ == TRUE ) {                                         // Si estamos esperando respuesta no hacemos nada.
      return FALSE;
    }
    
    if( forward == FALSE ) {                                              // Generamos el RREQ por primera vez (es decir, cuando se genera el paquete)
      aodv_hdr->seq      = rreq_seq_++;                                   // Aumentamos numero de secuencia
      aodv_hdr->dest     = dest;                                          // Asginamos el destino
      aodv_hdr->src      = call AMPacket.address();                       // Asignamos la fuente del mensaje
      aodv_hdr->hop      = 1;                                             // En un inicio inicializamos el numero de saltos a 1
      add_rreq_cache( aodv_hdr->seq, aodv_hdr->dest, aodv_hdr->src, 0 );
    } else {                                                              // Enrutamos/reenviamos el RREQ
      aodv_hdr->hop++; 		                                                // En caso de que solo debamos encaminar, solo debemos aumentar el numero de saltos
    }
    
    if (!send_pending_) {			                                            // Si no estamos pendiente de envio...
      if( call SendRREQ.send(TOS_BCAST_ADDR, p_rreq_msg_, 
                                    AODV_RREQ_HEADER_LEN) == SUCCESS) {   // Intentamos enviar hasta que lo hacemos bien
        printf( "%s\t AODV: sendRREQ()\n", "");
        send_pending_ = TRUE;                                             // Nos quedamos en estado de espera
        return TRUE;
      }
    }
    
    rreq_pending_ = TRUE;   
    rreq_retries_ = AODV_RREQ_RETRIES;                                    // Resetea los reintentos a 3
    return FALSE;
  }
  
  
  //--------------------------------------------------------------------------------------------------------------------------
  //  sendRREP: Reenvia/enruta el RREP hacia el siguiente salto del origen del RREQ para establecer e informar de la ruta.
  //--------------------------------------------------------------------------------------------------------------------------
  bool sendRREP( am_addr_t dest, bool forward ){
    
    printf( "%s\t AODV: sendRREP() dest: %d send_pending_: %d\n", 
                                      "", dest, send_pending_);
    
    if ( !send_pending_ ) {
      call PacketAcknowledgements.requestAck(p_rrep_msg_);
      if( call SendRREP.send(dest, p_rrep_msg_, 
                                           AODV_RREP_HEADER_LEN) == SUCCESS) {
        printf( "%s\t AODV: sendRREP() to %d\n", "", dest);
        send_pending_ = TRUE;
        return TRUE;
      }
    }
    
    rrep_pending_ = TRUE;
    rrep_retries_ = AODV_RREP_RETRIES;
    return FALSE;
  }
  
  
  //---------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  sendRERR: si el nodo no consigue transmitir un mensaje antes de llegar al limite de reenvios, envia un paquete de tipo RERR al nodo origen/fuente del mensaje.
  //---------------------------------------------------------------------------------------------------------------------------------------------------------------------
  bool sendRERR( am_addr_t dest, am_addr_t src, bool forward ){               // Creacion y envio de un paquete de route Error si falla algun reenvio 
    aodv_rerr_hdr* aodv_hdr = (aodv_rerr_hdr*)(p_rerr_msg_->data);
    am_addr_t target;
    
    printf( "%s\t AODV: sendRERR() dest: %d\n", "", dest);
    
    aodv_hdr->dest = dest;
    aodv_hdr->src = src;
    
    target = get_next_hop( src );
    
    if (!send_pending_) {				                                             // Si no estamos pendiente de envio...
      if( call SendRERR.send(target, p_rerr_msg_, AODV_RERR_HEADER_LEN)) {   // ... y "no se que hace esa funcion"
        printf( "%s\t AODV: sendRREQ() to %d\n", "", target);
        send_pending_ = TRUE;                                                // "supongo que enviamos el mensaje de error"
        return TRUE;
      }
    }
    
    rerr_pending_ = TRUE;			                                               // Esperamos la respuesta del nodo origen del paquete primero 
    rerr_retries_ = AODV_RERR_RETRIES;
    return FALSE;
  }
  
  //---------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  resendRREQ: Reenvia el paquete de route discovery hasta que se acaba el número de reintentos 
  //---------------------------------------------------------------------------------------------------------------------------------------------------------------------
  task void resendRREQ() {                                // Reenvio de un  router discovery
    printf( "%s\t AODV: resendRREQ()\n", "");
    
    if(rreq_retries_ <= 0){                               // Intentamos renviar el mensaje Route discovery hasta que baja a 0 
      rreq_pending_ = FALSE;
      return;
    }
    rreq_retries_--;
    
    if ( !send_pending_ ) {
      if( call SendRREQ.send(TOS_BCAST_ADDR, p_rreq_msg_, AODV_RREQ_HEADER_LEN) ) {
        send_pending_ = TRUE;
        rreq_pending_ = FALSE;
      }
    }
  }
  
  //---------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  resendRREP: Reenvia el paquete de route replay hasta que se acaba el número de reintentos 
  //---------------------------------------------------------------------------------------------------------------------------------------------------------------------
  task void resendRREP(){		                                           // Renvio de un Route replay (RREP)
    am_addr_t dest = call AMPacket.destination( p_rrep_msg_ );
    if( rrep_retries_ == 0 ) {	                                       // Intentamos renviar el mensaje Route replay hasta que baja a 0 
      rrep_pending_ = FALSE;
      return;
    }
    rrep_retries_--;
    
    if ( !send_pending_ ) {
      call PacketAcknowledgements.requestAck( p_rrep_msg_ );
      if( call SendRREP.send( dest, 
                               p_rrep_msg_, AODV_RREP_HEADER_LEN) == SUCCESS) {
        printf( "%s\t AODV: resendRREP() to %d\n", "", dest);
        send_pending_ = TRUE;
        rrep_pending_ = FALSE;
      }
    }
  }
  
  //---------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  resendRRER: Reenvia el paquete de route error hasta que se acaba el número de reintentos 
  //---------------------------------------------------------------------------------------------------------------------------------------------------------------------
  task void resendRERR(){		                                           // Renvio de un Route error (RERR) 
    am_addr_t dest = call AMPacket.destination( p_rerr_msg_ );
    if( rerr_retries_ == 0 ) {	                                       // Intentamos renviar el mensaje Route error hasta que baja a 0 
      rerr_pending_ = FALSE;
      return;
    }
    rerr_retries_--;
    
    if ( !send_pending_ ) {
      call PacketAcknowledgements.requestAck( p_rerr_msg_ );
      if( call SendRERR.send( dest, 
                               p_rerr_msg_, AODV_RERR_HEADER_LEN) == SUCCESS) {
        printf( "%s\t AODV: resendRERR() to %d\n", "");
        send_pending_ = TRUE;
        rerr_pending_ = FALSE;
      }
    }
  }
  
  
  //----------------------------------------------------------------------------------------------------------------------------------------------
  //  resendMSG: está función se desencadena cuando vence el temporizador correspondiente. Si el número de reenvíos posibles llega a 0, 
  //  la transmisión será cancelada. Si no, el mensaje en caché (almacenado) será retransmitido.
  //----------------------------------------------------------------------------------------------------------------------------------------------
  void resendMSG() {
    if( msg_retries_ == 0 ) {
      msg_pending_ = FALSE;
      return;
    }
    msg_retries_--;
    call PacketAcknowledgements.requestAck( p_aodv_msg_ );                          // Transmite el mensaje y lo reintenrta hasta que recibe el ack del nodo destino 
    if( !send_pending_ ) {
      if( call SubSend.send( call AMPacket.destination(p_aodv_msg_),
                        p_aodv_msg_,
                        call Packet.payloadLength(p_aodv_msg_) ) == SUCCESS ) {
        printf( "%s\t AODV: resendMSG() broadcast\n", "");
        send_pending_ = TRUE;
        msg_pending_ = FALSE;
      }
    }
  }
  
  //----------------------------------------------------------------------------------------------------------------------------------------------
  //  get_rreq_cache_index: función que devuelve el valor del indice del vector de la tabla de reenvio
  //----------------------------------------------------------------------------------------------------------------------------------------------
  uint8_t get_rreq_cache_index( am_addr_t src, am_addr_t dest ){ 
    int i;
    for( i=0 ; i < AODV_RREQ_CACHE_SIZE ; i++ ) {
      if( rreq_cache_[i].src == src && rreq_cache_[i].dest == dest ) {
        return i;
      }
      return INVALID_INDEX;
    }
  }
  
  //----------------------------------------------------------------------------------------------------------------------------------------------
  //  is_rreq_cached: función que comprueba si la entrada en la tabla caché ya está incluida
  //----------------------------------------------------------------------------------------------------------------------------------------------
  bool is_rreq_cached( aodv_rreq_hdr* rreq_hdr ) {
    int i;
    
    for( i=0; i < AODV_RREQ_CACHE_SIZE ; i++ ) {
      if( rreq_cache_[i].dest == INVALID_NODE_ID ) {
        return TRUE;
      }
      if( rreq_cache_[i].src == rreq_hdr->src && rreq_cache_[i].dest == rreq_hdr->dest ) {
        if( rreq_cache_[i].seq < rreq_hdr->seq || 
           ( rreq_cache_[i].seq == rreq_hdr->seq && rreq_cache_[i].hop > rreq_hdr->hop )) {
    // Esto es un nuevo RREQ
	  return TRUE;
        } else {
          return FALSE;
        }
      }
    }
    return TRUE;
  }
  
  //----------------------------------------------------------------------------------------------------------------------------------------------
  //  add_rreq_cache: esta función añade una fila a la tabla de reenvio del nodo o la actualiza
  //----------------------------------------------------------------------------------------------------------------------------------------------
  bool add_rreq_cache( uint8_t seq, am_addr_t dest, am_addr_t src, uint8_t hop ) {
    uint8_t i;
    uint8_t id = AODV_RREQ_CACHE_SIZE;
    
    for( i=0; i < AODV_RREQ_CACHE_SIZE-1 ; i++ ) {
      if( rreq_cache_[i].src == src && rreq_cache_[i].dest == dest ) {
        id = i;
        break;
      }
      if( rreq_cache_[i].dest == INVALID_NODE_ID )
      break;
    }
    
    if( id != AODV_RREQ_CACHE_SIZE ) {											                 // Actualiza la fila de la cache si ya tiene una entrada para el par origen-destino 
      if( rreq_cache_[i].src == src && rreq_cache_[i].dest == dest ) {
        if( rreq_cache_[id].seq < seq || rreq_cache_[id].hop > hop ) {
          rreq_cache_[id].seq = seq;
          rreq_cache_[id].hop = hop;
          rreq_cache_[i].ttl  = AODV_RREQ_CACHE_TTL;
          return TRUE;
        }
      }
    } else if( i != AODV_RREQ_CACHE_SIZE ) {									               // Nueva entrada en la caché
      rreq_cache_[i].seq  = seq;
      rreq_cache_[i].dest = dest;
      rreq_cache_[i].src  = src;
      rreq_cache_[i].hop  = hop;
      rreq_cache_[i].ttl  = AODV_RREQ_CACHE_TTL;
      return TRUE;
    }
    
    print_rreq_cache();
    return FALSE;
  }
  
  
  //----------------------------------------------------------------------------------------------------------------------------------------------
  //  del_rreq_cache: esta función borra la fila de la cache anulando sus valores y poniendolos por defecto 
  //----------------------------------------------------------------------------------------------------------------------------------------------
  void del_rreq_cache( uint8_t id ) {
    uint8_t i;
    
    for(i = id; i< AODV_ROUTE_TABLE_SIZE-1; i++) {
      if(rreq_cache_[i+1].dest == INVALID_NODE_ID) {
        break;
      }
      rreq_cache_[i] = rreq_cache_[i+1];
    }
    
    rreq_cache_[i].dest = INVALID_NODE_ID;
    rreq_cache_[i].src = INVALID_NODE_ID;
    rreq_cache_[i].seq  = 0;
    rreq_cache_[i].hop  = 0;
    
    print_rreq_cache();
  }
  
  
  //-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  update_rreq_cache: esta función es llamada periodicamente por el temporizador. Si el valor del TTL de una entidad "rreq_cache" es 0, la entidad será eliminada
  //-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  task void update_rreq_cache() {
    uint8_t i;
    for( i=0 ; i < AODV_RREQ_CACHE_SIZE-1 ; i++ ) {
      if( rreq_cache_[i].dest == INVALID_NODE_ID ){
	      break;                                          // Salimos
      }
      else if( rreq_cache_[i].ttl-- == 0 ){
        del_rreq_cache(i);		                          // Borramos el elemento de la cache de route request
      }
    }
  }
  
  
  //-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  get_route_table_index: función que devuelve el índice asociado al destino del mensaje
  //-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  uint8_t get_route_table_index( am_addr_t dest ) {
    int i;
    for(i=0; i< AODV_ROUTE_TABLE_SIZE; i++) {           // Recorre recursivamente la tabla de enrutamiento buscando el identifcador del destino y lo devuelve
      if(route_table_[i].dest == dest)  
        return i;
    }
    return INVALID_INDEX;
  }
  
  //-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  del_route_table: función que borra una entrada de la tabla de enrutamiento
  //-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  void del_route_table( am_addr_t dest ) {                       // Parametros de entrada -> Entrada de la tabla a borrar
    uint8_t i;
    uint8_t id = get_route_table_index( dest );                  // Se obtiene el identificador en la tabla
    
    printf( "%s\t AODV: del_route_table() dest:%d\n",
                                       "", dest);
    
    for(i = id; i< AODV_ROUTE_TABLE_SIZE-1; i++) {               // Se recorre recursivamente la tabla de enrutamiento...
      if(route_table_[i+1].dest == INVALID_NODE_ID) {            // ...cuando se encuentra la entrada salimos del for...
        break;
      }
      route_table_[i] = route_table_[i+1];
    }
    
    route_table_[i].dest = INVALID_NODE_ID;                      // Se cambia en dicha entrada los valores de destino y siguiente salto a un numero invalido predefinidio
    route_table_[i].next = INVALID_NODE_ID;
    route_table_[i].seq  = 0;				                             // Se cambia en dicha entrada los valores de numero de secuencia y numero de saltos a 0
    route_table_[i].hop  = 0;
    
    print_route_table();                                         // Muestra la tabla de enrutamiento
  }
  
  
	//-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  add_route_table: función que si recibe información de una nueva ruta o sobre la actualización de la información de una ruta ya existente, 
  //  la añade a la tabla de enrutamiento (Falta código por mirar).
  //-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  bool add_route_table( uint8_t seq, am_addr_t dest, am_addr_t nexthop, uint8_t hop ) {   // Parametros de entrada-> Numero de secuencia, destino,siguiente salto y numero de saltos
    uint8_t i;
    uint8_t id = AODV_ROUTE_TABLE_SIZE;                                                   // Por defecto 10
    
    printf( "%s\t AODV: add_route_table() seq:%d dest:%d next:%d hop:%d\n",
                                    "", seq, dest, nexthop, hop);
									
    for( i=0 ; i < AODV_ROUTE_TABLE_SIZE-1 ; i++ ) {
      if( route_table_[i].dest == dest ) {                                                // Primero recorre la tabla recursivamente para buscar si el destino ya existe dentro de la tabla
        id = i;
        break;
      }
      if( route_table_[i].dest == INVALID_NODE_ID ) {                                     // Si encuentra una entrada donde el destino es no valido, sale del bucle
        break;
      }
    }
    
    if( id != AODV_ROUTE_TABLE_SIZE ) {		                                                // Si el siguiente salto es igual a uno existente y cambia el numero del salto o la seq se actualiza 
      if( route_table_[id].next == nexthop ) {
        if( route_table_[id].seq < seq || route_table_[id].hop > hop ) {
          route_table_[id].seq = seq;
          route_table_[id].hop = hop;
          //route_table_[id].ttl = 0;
          return TRUE;
        }
      }
    } else if( i != AODV_ROUTE_TABLE_SIZE ) {                                             // Si no exite la entrada en la tabla de enrutamiento genera una nueva entrada 
      route_table_[i].seq  = seq;
      route_table_[i].dest = dest;
      route_table_[i].next = nexthop;
      route_table_[i].hop  = hop;
      //route_table_[i].ttl = 0;
      return TRUE;
    }
    return FALSE;
    print_route_table();
  }

  //--------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  get_next_hop: función que devuelve la dirección del siguiente nodo (siguiente salto) al que enviar el mensaje si la dirección existe en la tabla de enrutamiento.
  //--------------------------------------------------------------------------------------------------------------------------------------------------------------------
  am_addr_t get_next_hop( am_addr_t dest ) {                                  // Comprueba el destino y devuelve el siguiente salto
    int i;
    for( i=0 ; i < AODV_ROUTE_TABLE_SIZE ; i++ ) {
      if(route_table_[i].dest == dest) {
        return route_table_[i].next;
      }
    }
    return INVALID_NODE_ID;
  }
  
  //--------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  forwardMSG: el nodo reenvia/encamina un mensaje al siguiente nodo (salto) si el objetivo del mensaje no es él mismo 
  //--------------------------------------------------------------------------------------------------------------------------------------------------------------------
  error_t forwardMSG( message_t* p_msg, am_addr_t nexthop, uint8_t len ) {
    aodv_msg_hdr* aodv_hdr = (aodv_msg_hdr*)(p_msg->data);
    aodv_msg_hdr* msg_aodv_hdr = (aodv_msg_hdr*)(p_aodv_msg_->data);
    uint8_t i;
    
    if ( msg_pending_ ) {
      printf( "%s\t AODV: forwardMSG() msg_pending_\n", "");
      return FAIL;
    }
    printf( "%s\t AODV: forwardMSG() try to forward to %d \n", 
                                                    "", nexthop);
    
    // forward MSG
    msg_aodv_hdr->dest = aodv_hdr->dest;
    msg_aodv_hdr->src  = aodv_hdr->src;
    msg_aodv_hdr->app  = aodv_hdr->app;
    
    for( i=0 ; i < len-AODV_MSG_HEADER_LEN ; i++ ) {
      msg_aodv_hdr->data[i] = aodv_hdr->data[i];
    }
    
    call PacketAcknowledgements.requestAck(p_aodv_msg_);
    
    if( call SubSend.send(nexthop, p_aodv_msg_, len) == SUCCESS ) {
      printf( "%s\t AODV: forwardMSG() send MSG to: %d\n", 
                                                 "", nexthop);
      msg_retries_ = AODV_MSG_RETRIES;
      msg_pending_ = TRUE;
    } else {
      printf( "%s\t AODV: forwardMSG() fail to send\n", "");
      msg_pending_ = FALSE;
    }
    return SUCCESS;
  }
  
  //---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  AMSend.send: si existe una ruta al destino, el mensaje será enviado al siguiente salto (nodo) asociado a dicho destino. Si no, el nodo reenviará el mensaje RREQ en difusión. 
  //---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  command error_t AMSend.send[am_id_t id](am_addr_t addr, message_t* msg, uint8_t len) {
    uint8_t i;
    aodv_msg_hdr* aodv_hdr = (aodv_msg_hdr*)(p_aodv_msg_->data);
    am_addr_t nexthop = get_next_hop( addr );
    am_addr_t me = call AMPacket.address();
    
    printf("AODV: AMSend.send() dest: %u id: %x len: %d nexthop: %u\n", id, len, nexthop);
    
    if( addr == me ) {
      return SUCCESS;
    }
    /* Si el siguiente salto (nodo) para el destino fiajado no existe, el RREQ será difundido */ 
    if( nexthop == INVALID_NODE_ID ) {
      if( !rreq_pending_ ) {
        printf("AODV: AMSend.send() a new destination\n"); 
                                                             
        sendRREQ( addr, FALSE );
       return SUCCESS;
      }
      return FAIL;
    }
    printf( "%s\t AODV: AMSend.send() there is a route to %d\n", "", addr);
    aodv_hdr->dest = addr;
    aodv_hdr->src  = me;
    aodv_hdr->app  = id;
    
    for( i=0;i<len;i++ ) {
      aodv_hdr->data[i] = msg->data[i];
    }
    
    call PacketAcknowledgements.requestAck(p_aodv_msg_);
    
    if( !send_pending_ ) {
      if( call SubSend.send( nexthop, p_aodv_msg_, len + AODV_MSG_HEADER_LEN ) == SUCCESS ) {
        send_pending_ = TRUE;
        return SUCCESS;
      }
      msg_pending_ = TRUE;
    }
    return FAIL;
  }
  
  //--------------------------------------------------------------------------------------------------------------------------------------------------------
  //  SendRREQ.sendDone: función que hace que, si el mensaje RREQ se ha transmitido correctamente, se liberen los mensajes RREQ y SEND pendientes
  //--------------------------------------------------------------------------------------------------------------------------------------------------------
  event void SendRREQ.sendDone(message_t* p_msg, error_t e) {
    printf( "%s\t AODV: SendRREQ.sendDone()\n", "");
    send_pending_ = FALSE;
    rreq_pending_ = FALSE;
    //call Leds.led0Toggle();
    //call Leds.led1Toggle();
    //call Leds.led2Toggle();
  }
  
  //--------------------------------------------------------------------------------------------------------------------------------------------------------
  //  SendRREP.sendDone: función que hace que, si el mensaje RREP se ha transmitido correctamente, se liberen los mensajes RREP y SEND pendientes
  //--------------------------------------------------------------------------------------------------------------------------------------------------------
  event void SendRREP.sendDone(message_t* p_msg, error_t e) {
    printf( "%s\t AODV: SendRREP.sendDone()\n", "");
    send_pending_ = FALSE;
    if( call PacketAcknowledgements.wasAcked(p_msg) )
      rrep_pending_ = FALSE;
    else
      rrep_pending_ = TRUE;
  }
  
  
  //--------------------------------------------------------------------------------------------------------------------------------------------------------
  //  SendRRER.sendDone: función que hace que, si el mensaje RRER se ha transmitido correctamente, se liberen los mensajes RRER y SEND pendientes
  //--------------------------------------------------------------------------------------------------------------------------------------------------------
  event void SendRERR.sendDone(message_t* p_msg, error_t e) {
    printf( "%s\t AODV: SendRERR.sendDone() \n", "");
    send_pending_ = FALSE;
    if( call PacketAcknowledgements.wasAcked(p_msg) )
      rerr_pending_ = FALSE;
    else
      rerr_pending_ = TRUE;
  }
  
  
  //-----------------------------------------------------------------------------------------------------------------------------------------------------------
  //  ReceiveRREQ.receive: si el destino del mensaje RREQ soy yo, enviaré el RREP de vuelta para establecer la ruta inversa. Si no, reenviaré/enrutaré el 
  //  mensaje RREQ al siguiente salto (nodo).
  //-----------------------------------------------------------------------------------------------------------------------------------------------------------
  event message_t* ReceiveRREQ.receive( message_t* p_msg, void* payload, uint8_t len ) {
    bool cached = FALSE;
    bool added  = FALSE;
    
    am_addr_t me  = call AMPacket.address();
    am_addr_t src = call AMPacket.source( p_msg );
    aodv_rreq_hdr* aodv_hdr      = (aodv_rreq_hdr*)(p_msg->data);
    aodv_rreq_hdr* rreq_aodv_hdr = (aodv_rreq_hdr*)(p_rreq_msg_->data);
    aodv_rrep_hdr* rrep_aodv_hdr = (aodv_rrep_hdr*)(p_rrep_msg_->data);
    
    printf( "%s\t AODV: ReceiveRREQ.receive() src:%d dest: %d \n", "", aodv_hdr->src, aodv_hdr->dest);
    
    if( aodv_hdr->hop > AODV_MAX_HOP ) {
      return p_msg;
    }
    
    /* Si el mensaje RREQ recibido ya lo he recibido anteriormente, será ignorado */
    if( !is_rreq_cached( aodv_hdr ) ) {
      printf( "%s\t AODV: ReceiveRREQ.receive() already received one\n", "");
      return p_msg;
    }
    
    /* Añado la información de la ruta en la tabla de enrutamiento */
    add_route_table( aodv_hdr->seq, src, src, 1 );
    added = add_route_table( aodv_hdr->seq, aodv_hdr->src, src, aodv_hdr->hop );
    
    cached = add_rreq_cache( aodv_hdr->seq, aodv_hdr->dest, aodv_hdr->src, aodv_hdr->hop );
    
    
    /* Si el destino del mensaje RREQ soy yo, enviaré el mensaje de RREP */
    if( aodv_hdr->dest == me && added ) {
      rrep_aodv_hdr->seq  = aodv_hdr->seq;
      rrep_aodv_hdr->dest = aodv_hdr->dest;
      rrep_aodv_hdr->src  = aodv_hdr->src;
      rrep_aodv_hdr->hop  = 1;
      sendRREP( src, FALSE );
      return p_msg;
    }
    
    // Si el mensaje RREQ no es para mi...
    if( !rreq_pending_ && aodv_hdr->src != me && cached ) {
      // forward RREQ
      rreq_aodv_hdr->seq  = aodv_hdr->seq;
      rreq_aodv_hdr->dest = aodv_hdr->dest;
      rreq_aodv_hdr->src  = aodv_hdr->src;
      rreq_aodv_hdr->hop  = aodv_hdr->hop + 1;
      call RREQTimer.stop();
      call RREQTimer.startOneShot( (call Random.rand16() % 7) * 10 );
    }
    
    return p_msg;
  }
  
  
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  ReceiveRREP.receive: si la dirección origen de un mensaje RREP soy yo, significa que la ruta hacia el destino está establecida. Si no, debo enrutar/reenviar el
  //  mensaje RREP hacia el siguiente salto (nodo).
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  event message_t* ReceiveRREP.receive( message_t* p_msg, void* payload, uint8_t len ) {
    aodv_rrep_hdr* aodv_hdr = (aodv_rrep_hdr*)(p_msg->data);
    aodv_rrep_hdr* rrep_aodv_hdr = (aodv_rrep_hdr*)(p_rrep_msg_->data);
    am_addr_t src = call AMPacket.source(p_msg);
    
    printf( "%s\t AODV: ReceiveRREP.receive() src: %d dest: %d \n", "", aodv_hdr->src, aodv_hdr->dest);
    if( aodv_hdr->src == call AMPacket.address() ) { // Si soy el destino del mensaje RREP...
      add_route_table( aodv_hdr->seq, aodv_hdr->dest, src, aodv_hdr->hop );
    } else { // Si no soy yo el destino...
      am_addr_t dest = get_next_hop( aodv_hdr->src );
      if( dest != INVALID_NODE_ID ) {
        // forward RREP
        rrep_aodv_hdr->seq  = aodv_hdr->seq;
        rrep_aodv_hdr->dest = aodv_hdr->dest;
        rrep_aodv_hdr->src  = aodv_hdr->src;
        rrep_aodv_hdr->hop  = aodv_hdr->hop++;
        
        add_route_table( aodv_hdr->seq, aodv_hdr->dest, src, aodv_hdr->hop );
        sendRREP( dest, TRUE );
      }
    }
    return p_msg;
  }
  
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  ReceiveRERR.receive: Cuando se recibe un un mensaje de Error se borra la entra de tabla de routing y se envia un mensaje de error si no es para nosotros
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  event message_t* ReceiveRERR.receive( message_t* p_msg, void* payload, uint8_t len ) {
    aodv_rerr_hdr* aodv_hdr = (aodv_rerr_hdr*)(p_msg->data);
    printf( "%s\t AODV: ReceiveRERR.receive()\n", "");
    del_route_table( aodv_hdr->dest );
    if( aodv_hdr->src != call AMPacket.address())
      sendRERR( aodv_hdr->dest, aodv_hdr->src, TRUE );
    
    return p_msg;
  }
  
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  AMSend.cancel: "HAY EXPLICAR BIEN QUE HACE ESTA FUNCION"
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  command error_t AMSend.cancel[am_id_t id](message_t* msg) { 
    return call SubSend.cancel(msg);
  }
  
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  AMSend.maxPayloadLength: Funcion que devuelve el payload maximo para poder enviar un paquete
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  command uint8_t AMSend.maxPayloadLength[am_id_t id]() {
    return call Packet.maxPayloadLength();
  }
  
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  AMSend.getPayload: Funcion que devuelve un void  con el puntero al mensaje y al payload del mismo 
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  command void* AMSend.getPayload[am_id_t id](message_t* m, uint8_t len) {
    return call Packet.getPayload(m, 0);
  }
  
  /*
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  Receive.getPayload: Funcion que devuelve un void  con el puntero al mensaje y al payload del mismo 
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  command void * Receive.getPayload[uint8_t am](message_t *msg, uint8_t *len){
    return call Packet.getPayload(msg, len);
  }
  
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  Receive.payloadLength: funcion que devuelve el valor del payload
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  command uint8_t Receive.payloadLength[uint8_t am](message_t *msg){
    return call Packet.payloadLength(msg);
  }
  */
  
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  SubSend.sendDone: evento para el envio real de los mensajes
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  event void SubSend.sendDone(message_t* p_msg, error_t e) {
    aodv_msg_hdr* aodv_hdr = (aodv_msg_hdr*)(p_msg->data);
    bool wasAcked = call PacketAcknowledgements.wasAcked(p_msg);
    am_addr_t dest = call AMPacket.destination(p_aodv_msg_);
    
    printf( "%s\t AODV: SubSend.sendDone() dest:%d src:%d wasAcked:%d\n", "", aodv_hdr->dest, aodv_hdr->src, wasAcked);
    
    send_pending_ = FALSE;
    
    if ( msg_pending_ == TRUE && p_msg == p_aodv_msg_ ) {
      if ( wasAcked ) {
        msg_retries_ = 0;
        msg_pending_ = FALSE;
      } else {
        msg_retries_--;
        if( msg_retries_ > 0 ) {
          printf( "%s\t AODV: SubSend.sendDone() msg was not acked, resend\n", "");
          call PacketAcknowledgements.requestAck( p_aodv_msg_ );
          call SubSend.send( dest, p_aodv_msg_, call Packet.payloadLength(p_aodv_msg_) );
        } else {
          printf( "%s\t AODV: SubSend.sendDone() route may be corrupted\n", "");
          msg_pending_ = FALSE;
          del_route_table( dest );
          sendRERR( aodv_hdr->dest, aodv_hdr->src, FALSE );
        }
      }
    } else {
      signal AMSend.sendDone[aodv_hdr->app](p_msg, e);
    }
  }
  
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  SubSend.sendDone: evento para la recepcion real de los mensajes
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  event message_t* SubReceive.receive( message_t* p_msg, void* payload, uint8_t len ) {
    uint8_t i;
    aodv_msg_hdr* aodv_hdr = (aodv_msg_hdr*)(p_msg->data);
    
    printf( "%s\t AODV: SubReceive.receive() dest: %d src:%d\n", "", aodv_hdr->dest, aodv_hdr->src);
    
    if( aodv_hdr->dest == call AMPacket.address() ) {
      printf( "%s\t AODV: SubReceive.receive() deliver to upper layer\n", "");
      for( i=0;i<len;i++ ) {
        p_app_msg_->data[i] = aodv_hdr->data[i];
      }
      p_msg = signal Receive.receive[aodv_hdr->app]( p_app_msg_, p_app_msg_->data, len - AODV_MSG_HEADER_LEN );
    } else {
      am_addr_t nexthop = get_next_hop( aodv_hdr->dest );
      printf( "%s\t AODV: SubReceive.receive() deliver to next hop:%x\n", "", nexthop);
      /* Si hay un siguiente nodo de salto hacia el destino de un mensaje, el mensaje será reenviado/enrutado hacia dicho siguiente salto */
      if (nexthop != INVALID_NODE_ID) {
        forwardMSG( p_msg, nexthop, len );
      } 
    }
    return p_msg;
  }
  
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  AODVTimer.fired: evento para la expiración del timer de AODV 
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  event void AODVTimer.fired() {
    //printf("%s\t AODV: Expira el timer de AODV\n", "");
    if( rreq_pending_ ){
      post resendRREQ();
    }
    
    if( rrep_pending_ ) {
      post resendRREP();
    }
    
    if( rreq_pending_ ) {
      post resendRERR();
    }
    
    post update_rreq_cache();
  }
  
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  RREQTimer.fired: evento donde se avisa que el tiempo del RREQ se ha acabado y se envia un RREQ
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  event void RREQTimer.fired() {
    printf( "%s\t AODV: RREQTimer.fired()\n", "");
    sendRREQ( 0 , TRUE );
  }
  
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  defaults: Funciones asociadas por defecto al evento de AMSend.sendDone y Receive.receive donde no 
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  default event void AMSend.sendDone[uint8_t id](message_t* msg, error_t err) {
    return;
  }
  
  default event message_t* Receive.receive[am_id_t id](message_t* msg, void* payload, uint8_t len) {
    return msg;
  }
  
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  print_route_table: Funcion que recorre la tabla de reenvio y la imprime
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  void print_route_table(){    
    uint8_t i;
    for( i=0; i < AODV_ROUTE_TABLE_SIZE ; i++ ) {
      if(route_table_[i].dest == INVALID_NODE_ID)
        break;
      printf("%s\t TABLA DE RUTAS: ROUTE_TABLE i: %d: dest: %d next: %d seq:%d hop: %d \n", 
           "", i, route_table_[i].dest, route_table_[i].next, 
                 route_table_[i].seq, route_table_[i].hop );
    }
  }
  
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  //  print_rreq_cache: Funcion que recorre la tabla de rreq y la imprime
  //----------------------------------------------------------------------------------------------------------------------------------------------------------------------
  void print_rreq_cache() { 
    uint8_t i;
    for( i=0 ; i < AODV_RREQ_CACHE_SIZE ; i++ ) {
      if(rreq_cache_[i].dest == INVALID_NODE_ID )
        break;
      printf("%s\t RREQ CACHE: RREQ_CACHE i: %d: dest: %d src: %d seq:%d hop: %d \n", 
           "", i, rreq_cache_[i].dest, rreq_cache_[i].src, rreq_cache_[i].seq, rreq_cache_[i].hop );
    }
  }
}


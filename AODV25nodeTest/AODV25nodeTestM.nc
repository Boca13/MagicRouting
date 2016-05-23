/*
 * Copyright (c) MagicRouting
 * Author: Jesús Bocanegra, David Barranco, Alberto Flores, Adrian Marcelo y Enrique Gil
 * Date: 14/05/2016
 * Version: 1.2
 * Published under the terms of the GNU General Public License (GPLv2).
 */

 #include "printf.h"
 #include "libreria.h"


module AODV25nodeTestM {
  uses {
    interface Boot;
    interface SplitControl;
    interface Timer<TMilli> as MilliTimer;
    interface AMSend;
    interface Receive;
    interface Leds;	
    interface Read<uint16_t> as Temperature;
    interface Read<uint16_t> as Humidity;
    interface Read<uint16_t> as ReadVisible;
    interface CC2420Packet; 
    interface Packet;
  }
}

implementation {
  
  message_t pkt;
  message_t* p_pkt;
  float T;		
  float L;	
  float H;
  uint16_t seq; 

	
  uint16_t src  = 0x0007;
  uint16_t dest = 0x0001;
  uint16_t dest2 = 0x0002;
  
  event void Boot.booted() {
    call SplitControl.start();
  }
  
  
  event void SplitControl.startDone(error_t err) {
    if (err == SUCCESS) {
      printf("He iniciado la radio correctamente, salu2");
      printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
        printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
        printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
        printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
        printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
        printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
        printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
      p_pkt = &pkt;
      seq=0;	
      call Leds.led0Toggle();
      call Leds.led0Toggle();
      call Leds.led1Toggle();
      call Leds.led1Toggle();
      call Leds.led2Toggle();
      call Leds.led2Toggle();


      if( TOS_NODE_ID == 0x0007 ){
        call MilliTimer.startPeriodic(2048);
        printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
        printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
        printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
        printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
        printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
        printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
        printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
      }
    } else {
      call Leds.led1Toggle();
      call SplitControl.start();
    }
  }
  
  event void SplitControl.stopDone(error_t err) {
    // No hacemos nada
  }
  
   //Evento que se genera al pedir la medida de la temperatura (100% INVENTADO)
  event void Temperature.readDone(error_t result,uint16_t val) {
    T=val; // lee el valor de la temperatura
  }
   //Evento que se genera al pedir la medida de la Luminosidad (100% INVENTADO)
  event void ReadVisible.readDone(error_t result,uint16_t val) {
    L=val; // lee el valor de la humedad
  }
    //Evento que se genera al pedir la medida de la humedad 
 event void Humidity.readDone(error_t result,uint16_t val) {
    H=val; // lee el valor de la humedad
    
  }
	uint16_t getRssi(message_t *msg){
	return (uint16_t) call CC2420Packet.getRssi(msg);
	} 

  event void MilliTimer.fired() {
	

    printf("%s\t\t APPS: Main MilliTimer fired()\n","");
    call Leds.led1Toggle();    
    printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
	if(TOS_NODE_ID != 0x0001)
	{
  
  	PktMeasure* Pktmedida = (PktMeasure*)(call AMSend.getPayload(&pkt, sizeof(PktMeasure)) );
	if (Pktmedida == NULL) {
		return;
     	 }
 
      	Pktmedida->dest= 0x0001;
      	Pktmedida->src =  TOS_NODE_ID;
	call Temperature.read();
	call Humidity.read();
	call ReadVisible.read();
        seq=(seq+1);
	Pktmedida->temperatura=T;
	Pktmedida->humedad=H;
	Pktmedida->luminosidad=L;
	Pktmedida->rssi= getRssi (&pkt);;
	Pktmedida->blong=16;

	Pktmedida->seq=seq;




	printf("%s\t\t Voy a enviar el paquete de datos\n", "");	
	call AMSend.send(dest, &pkt, sizeof(PktMeasure));  
  
 	 }
  
  }

 /* command void* Packet.getPayload[am_id_t id](message_t* m, uint8_t len) {
    return call Packet.getPayload(m, 0);
  }*/
  
  
  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
    printf("%s\t\t Main send Done\n", "");
    call Leds.led0Toggle();
  }
  
  event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
    
  uint16_t fuente=0;
  uint16_t destino=0;
  float temperatura=0;
  PktMeasure* bufPtr;
    printf("\t\t\t LONGITUD: %d ",len);
    printf("\t APPS: Recibo un paquete!!!\n");    
    call Leds.led2Toggle();
    if (len == sizeof(PktMeasure)) {
     bufPtr = (PktMeasure*)payload;
	fuente=bufPtr->src;	
	destino=bufPtr->dest;
        temperatura=bufPtr->temperatura;
	}
	printf("%s\t\t Datos recibidos fuente: %d destino :%d temperatura:%f \n", "",fuente,destino,temperatura);

    return msg;
  }
}


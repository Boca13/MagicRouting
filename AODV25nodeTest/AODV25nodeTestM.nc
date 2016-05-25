/*
 * Copyright (c) MagicRouting
 * Author: Jesús Bocanegra, David Barranco, Alberto Flores, Adrian Marcelo y Enrique Gil
 * Date: 14/05/2016
 * Version: 1.2
 * Published under the terms of the GNU General Public License (GPLv2).
 */

 #include "printf.h"
typedef nx_struct DataPacket{
	nx_uint16_t fuente;
	nx_uint16_t seq;
	nx_uint16_t humedad;

}DataPacket;


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
  bool busy = FALSE;
  message_t pkt;
	//mensaje pkt;
  
  
  uint16_t dest = 0x0005;
  uint16_t T;		
  uint16_t L;
  uint16_t H;
  uint16_t seq=0; 
  
  
  event void Boot.booted() {
    call SplitControl.start();
  }
  
  
  event void SplitControl.startDone(error_t err) {
    if (err == SUCCESS) {
    
      
      
    	printf("Inicio del nodo: %d\n", TOS_NODE_ID);

      if( TOS_NODE_ID != 0x0002 ){ 
        call MilliTimer.startPeriodic(1024);
      }

    } else {

      call SplitControl.start();
    }
  }
  
  event void SplitControl.stopDone(error_t err) {
    // No hacemos nada
  }


	
  event void Humidity.readDone(error_t result,uint16_t val) {
    T=val; // lee el valor de la humedad
   
  }

//Evento que se genera al pedir la medida de la temperatura (100% INVENTADO)
  event void Temperature.readDone(error_t result,uint16_t val) {
    H=val; // lee el valor de la humedad
  }
  //Evento que se genera al pedir la medida de la Luminosidad (100% INVENTADO)
  event void ReadVisible.readDone(error_t result,uint16_t val) {
    L=val; // lee el valor de la humedad
  }
  


  
  
  event void MilliTimer.fired() {
  	

    printf("%s\t\t APPS: Main MilliTimer fired()\n","");
    call Leds.led1Toggle();    
    call Temperature.read();
    printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
	//pkt.temperatura = 25;
	//printf("Envio un paquete al nodo %d con humedad %d\n", dest, pkt.temperatura);
    //printf("Tamaño del paquete: %d\n\n\n",sizeof(message_t));
    //call AMSend.send(dest, p_pkt, 8);
    if(!busy){
     DataPacket* btrpkt = (DataPacket*)(call AMSend.getPayload(&pkt, sizeof(DataPacket)));
     btrpkt->humedad = 25;
     btrpkt->seq = seq;
     btrpkt->fuente = TOS_NODE_ID;
     call AMSend.send(dest,&pkt,sizeof(DataPacket));     
}}

	/*
	printf("%s\t\t APPS: Main MilliTimer fired()\n","");
    call Leds.led1Toggle();    
	call Temperature.read();
    printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
	if(TOS_NODE_ID == 0x0007)
	{
  
  	//pkt = (PktMeasure*)(call AMSend.getPayload(&mensaje, sizeof(mensaje)) );
	//if (pkt == NULL) {
	//	return;}
       	
	
        //seq=(seq+1);
	pkt->temperatura=T;
	//Pktmedida->humedad=H;
	//Pktmedida->luminosidad=L;
	//Pktmedida->rssi= getRssi (&pkt);
	//Pktmedida->blong=16;

	//Pktmedida->seq=seq;
	printf("%s\t\t Voy a enviar el paquete de datos\n", "");	
	call AMSend.send(0x000A, &pkt, sizeof(PktMeasure));
	} */
    
  
  
  
  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
    printf("%s\t\t Main send Done\n", "");
    seq++;
    call Leds.led0Toggle();
    
  }
  
  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
  
    
    return bufPtr;
}


	
  
}


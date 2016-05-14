/*
 * Copyright (c) MagicRouting
 * Author: Jesús Bocanegra, David Barranco, Alberto Flores, Adrian Marcelo y Enrique Gil
 * Date: 14/05/2016
 * Version: 1.2
 * Published under the terms of the GNU General Public License (GPLv2).
 */

 #include "printf.h"

module AODV25nodeTestM {
  uses {
    interface Boot;
    interface SplitControl;
    interface Timer<TMilli> as MilliTimer;
    interface AMSend;
    interface Receive;
    interface Leds;
  }
}

implementation {
  
  message_t pkt;
  message_t* p_pkt;
  
  uint16_t src  = 0x0007;
  uint16_t dest = 0x000A;
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
      call Leds.led0Toggle();
      call Leds.led0Toggle();
      call Leds.led1Toggle();
      call Leds.led1Toggle();
      call Leds.led2Toggle();
      call Leds.led2Toggle();


      if( TOS_NODE_ID == 0x0007 ){
        call MilliTimer.startPeriodic(1024);
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
  
  
  event void MilliTimer.fired() {
    printf("%s\t\t APPS: Main MilliTimer fired()\n","");
    call Leds.led1Toggle();    
    printf("/t TOS NODE ID: %x\n",TOS_NODE_ID );
    call AMSend.send(dest, p_pkt, 5);    
  }
  
  
  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
    printf("%s\t\t Main send Done\n", "");
    call Leds.led0Toggle();
  }
  
  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    printf("\t\t\t LONGITUD: %d ",len);
    printf("\t APPS: Recibo un paquete!!!\n");    
    call Leds.led2Toggle();
    
    return bufPtr;
  }
}


/*
 * Copyright (c) 2008 Junseok Kim
 * Author: Junseok Kim <jskim@usn.konkuk.ac.kr> <http://usn.konkuk.ac.kr/~jskim>
 * Date: 2008/05/30
 * Version: 0.0.1
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
  
  event void Boot.booted() {
    call SplitControl.start();
  }
  
  
  event void SplitControl.startDone(error_t err) {
    if (err == SUCCESS) {
      printf("He iniciado la radio correctamente, salu2");
      p_pkt = &pkt;
      if( TOS_NODE_ID == src )
        call MilliTimer.startPeriodic(1024);
    } else {
      call Leds.led1Toggle();
      call SplitControl.start();
    }
  }
  
  event void SplitControl.stopDone(error_t err) {
    // do nothing
  }
  
  
  event void MilliTimer.fired() {
    printf("%s\t APPS: MilliTimer.fired()\n","");    
    call AMSend.send(dest, p_pkt, 5);
  }
  
  
  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
    printf("%s\t APPS: sendDone!!\n", "");
    call Leds.led0Toggle();
    printf("Envio un paquete a no se donde");
  }
  
  
  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    printf("%s\t APPS: receive!!\n", "");
    call Leds.led0Toggle();
    return bufPtr;
  }
}


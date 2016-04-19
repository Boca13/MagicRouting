/*
 * Copyright (c) 2008 Junseok Kim
 * Author: Junseok Kim <jskim@usn.konkuk.ac.kr> <http://usn.konkuk.ac.kr/~jskim>
 * Date: 2008/05/30
 * Version: 0.0.1
 * Published under the terms of the GNU General Public License (GPLv2).
 */
 
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
      dbg("APPS", "%s\t APPS: startDone %d.\n", sim_time_string(), err);
      p_pkt = &pkt;
      if( TOS_NODE_ID == src )
        call MilliTimer.startPeriodic(1024);
    } else {
      call SplitControl.start();
    }
  }
  
  event void SplitControl.stopDone(error_t err) {
    // do nothing
  }
  
  
  event void MilliTimer.fired() {
    dbg("APPS", "%s\t APPS: MilliTimer.fired()\n", sim_time_string());
    call Leds.led0Toggle();
    call AMSend.send(dest, p_pkt, 5);
  }
  
  
  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
    dbg("APPS", "%s\t APPS: sendDone!!\n", sim_time_string());
  }
  
  
  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    dbg("APPS", "%s\t APPS: receive!!\n", sim_time_string());
    return bufPtr;
  }
}


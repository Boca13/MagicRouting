/*
 * Copyright (c) MagicRouting
 * Author: Jesús Bocanegra, David Barranco, Alberto Flores, Adrian Marcelo y Enrique Gil
 * Date: 14/05/2016
 * Version: 1.2
 * Published under the terms of the GNU General Public License (GPLv2).
 */

 #include "printf.h"
 
configuration AODV25nodeTest {
}

implementation {
  components MainC, AODV25nodeTestM, AODV, LedsC;
  
  AODV25nodeTestM.Boot -> MainC.Boot;
  AODV25nodeTestM.SplitControl -> AODV.SplitControl;
  AODV25nodeTestM.AMSend -> AODV.AMSend[1];
  AODV25nodeTestM.Receive -> AODV.Receive[1];
  AODV25nodeTestM.Leds -> LedsC;
  
  components new TimerMilliC();
  AODV25nodeTestM.MilliTimer -> TimerMilliC;
}


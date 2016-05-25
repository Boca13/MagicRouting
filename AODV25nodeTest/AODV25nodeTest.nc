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
components new SensirionSht11C() as Sht11;
   components new HamamatsuS1087ParC() as TotalSolarC;
   components CC2420ActiveMessageC;
  
  AODV25nodeTestM.Boot -> MainC.Boot;
  AODV25nodeTestM.SplitControl -> AODV.SplitControl;
  AODV25nodeTestM.AMSend -> AODV.AMSend[1];
  AODV25nodeTestM.Receive -> AODV.Receive[1];
  AODV25nodeTestM.Leds -> LedsC;
  AODV25nodeTestM.Temperature -> Sht11.Temperature;
  AODV25nodeTestM.Humidity -> Sht11.Humidity;
  AODV25nodeTestM.ReadVisible -> TotalSolarC;
  AODV25nodeTestM -> CC2420ActiveMessageC.CC2420Packet;
  
  components new TimerMilliC();
  AODV25nodeTestM.MilliTimer -> TimerMilliC;
}


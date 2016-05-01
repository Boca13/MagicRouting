/*
 * Copyright (c) 2006 Washington University in St. Louis.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 * - Neither the name of the copyright holders nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL
 * THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 */
 
/**
 *
 * This application is used to test the basic functionality of the printf service.  
 * It is initiated by calling the start() command of the SplitControl interface 
 * provided by the PrintfC component.  After starting the printf service, calls to 
 * the standard c-style printf command are made to print various strings of text 
 * over the serial line.  Only upon calling PrintfFlush.flush() does the data 
 * actually get sent out over the serial line.
 *
 * @author Kevin Klues (klueska@cs.wustl.edu)
 * @version $Revision: 1.3 $
 * @date $Date: 2010/06/29 22:07:40 $
 */

#include "printf.h"
module GatewayC {
  uses {
    interface Boot;
  }
	uses interface Timer<TMilli> as Timer0;
}
implementation {
	
  uint8_t dummyVar1 = 0;
  uint16_t dummyVar2 = 0;
  uint32_t dummyVar3 = 0;

	typedef struct {
		uint8_t cabecera;
		uint16_t source;
		uint32_t destination;
		float x;
		float y;
		char s[1400];
	}paqueteIN;

	paqueteIN pkt = {'c', 161, 1236521, 123.987, 21.8745,"Anyone familiar with TinyOS knows that debugging applications has traditionally been a very arduous, if not stressful process. While simulators like TOSSIM can be used to help verify the logical correctness of a program, unforseen problems inevitably arise once that program is deployed on real hardware. Debugging such a program typically involves flashing the three available LEDs in some intricate sequence or resorting to line by line analysis of a running program through the use of a JTAG."};

  void sendByte(char b) {
		printf("%c",b);
		printfflush();
	}

	void sendArray(uint8_t *b, uint16_t l) {
		uint16_t c;
		for(c=0; c<l; c++) {
			printf("%c",b[c]);
		}
		printfflush();
	}

  void sendString(char *s) {
		printf("%s",s);
		printfflush();
	}

  event void Boot.booted() {
		call Timer0.startPeriodic( 5000 );
  }

  event void Timer0.fired() {
	sendArray((char*)&pkt,sizeof(pkt));

		if(dummyVar1++==0)
  		printf("Tamaño del pkt: %d\n",sizeof(pkt));
		else if(dummyVar1==1)
			sendArray((char*)&pkt,sizeof(pkt));
		else
			sendByte(dummyVar1);
}
}


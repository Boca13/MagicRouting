
#ifndef libreria_H
#define libreria_H

typedef nx_struct PktMeasure{
	nx_uint16_t src;
	nx_uint16_t dest;
	nx_uint16_t seq;
	nx_uint16_t blong;	
	nx_float temperatura;
	nx_float humedad;    
	nx_float luminosidad;
	nx_float rssi;       
	} PktMeasure;

#endif

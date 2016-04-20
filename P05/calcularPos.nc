// CONSTANTES
// Número de nodos estáticos en la red
#define N_NODOS	3
// Constantes para el cálculo de la distancia mediante el RSSI
#define RSSI_A	-10.302
#define RSSI_B	-1.678
// Factor de potencia
#define P		1

// Estrucutra punto para representar posiciones
typedef struct {
	float x;
	float y;
}punto;

// Posiciones de los nodos estáticos
const punto posiciones[N_NODOS] = {{0.0, 0.0}, {100.0, 50.0}, {50.0, 100.0}};

// Pesos que se calcularán para obtener la posición del nodo móvil
float pesos[N_NODOS];

// Medidas del RSSI obtenidas de los nodos estáticos
int16_t rssi[N_NODOS];

punto calcularPos()
{
	uint8_t j;
	punto posicion = {0.0, 0.0}; // Resultado de la función
	punto numerador = {0.0, 0.0};
	float sumPesos = 0.0; // Denominador
	// Bucle que itera para cada nodo estático
	for(j = 0; j < N_NODOS; j++)
	{
		// Calcular pesos
		pesos[j] = 1/(pow10((rssi[j]-RSSI_B)/RSSI_A));
		
		// Añadir nuevo peso a la suma (denominador de L)
		sumPesos += pesos[j];
		
		// Calcular coordenadas (numerador)
		numerador.x += (pesos[j]*posiciones[j].x);
		numerador.y += (pesos[j]*posiciones[j].y);
		
		
	}
	// Terminar de calcular distancias (denominador)
	posicion.x = numerador.x/sumPesos;
	posicion.y = numerador.y/sumPesos;
	return posicion;
}
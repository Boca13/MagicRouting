// SerialGateway project main.go
package main

import (
	"bytes"
	"container/list"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"strconv"
)

import "github.com/jacobsa/go-serial/serial"

const MAX_PACKET = 1500
const TAM_PAQUETEAPP = 48

// Maps de listas
var temperaturas map[uint16]*list.List = make(map[uint16]*list.List)
var humedades map[uint16]*list.List = make(map[uint16]*list.List)
var luminosidades map[uint16]*list.List = make(map[uint16]*list.List)
var rssis map[uint16]*list.List = make(map[uint16]*list.List)

//Lista de IDs
var ids []uint16 = make([]uint16, 1)

type PaqueteAPP struct {
	operacion uint8
	destino   uint16
	parametro [8]byte
	valor     [16]byte
}

type Paquete struct {
	origen  uint16
	destino uint16
	seq     uint16
	long    uint16 // Número de bytes en payload
	payload []byte
}

type PaqueteFlow struct {
	origen      uint16
	destino     uint16
	seq         uint16
	long        uint16 // Número de bytes en payload
	temperatura uint16
	humedad     uint16
	luminosidad uint16
	rssi        uint16
}

type ProtocoloAPP struct {
	puerto *SerialPort
	id     uint16
}

type SerialPort struct {
	id         uint16
	port       io.ReadWriteCloser
	flagCerrar bool
	seqcounter uint16
}

// Asigna un serialport al protocolo de aplicación
func (p *ProtocoloAPP) attach(puerto *SerialPort) {
	p.puerto = puerto
	p.id = puerto.id
}

func (p *ProtocoloAPP) enviar(operacion uint8, destino uint16, parametro string, valor string) error {
	pktserie := Paquete{p.id, destino, 0, TAM_PAQUETEAPP, nil}
	// Rellenar paquete APP
	bytesParametro := []byte(parametro)
	bytesValor := []byte(valor)
	var arrayParametro [8]byte
	var arrayValor [16]byte
	copy(bytesParametro[:], arrayParametro[0:7])
	copy(bytesValor[:], arrayValor[0:15])
	pktapp := PaqueteAPP{operacion, destino, arrayParametro, arrayValor}

	// Copiar pktapp a payload de pktserie
	buf := &bytes.Buffer{}
	err := binary.Write(buf, binary.BigEndian, pktapp)
	if err != nil {
		log.Println("Error enviando paquete de aplicación :", err)
		return err
	}
	copy(pktserie.payload[:], buf.Bytes())

	return p.puerto.enviar(pktserie)
}

func (s *SerialPort) inicializar(direccion uint16, puerto string) error {
	var err error
	s.id = direccion

	// Set up options.
	options := serial.OpenOptions{
		PortName:        puerto,
		BaudRate:        115200,
		DataBits:        8,
		StopBits:        1,
		MinimumReadSize: 1,
	}

	// Open the port
	s.port, err = serial.Open(options)
	if err != nil {
		log.Fatalf("Error al abrir el puerto serie: %v", err)
		return err
	}
	return nil
}

func (s *SerialPort) enviar(paquete Paquete) error {
	cabecera := make([]byte, 8)
	binary.BigEndian.PutUint16(cabecera, paquete.origen)
	binary.BigEndian.PutUint16(cabecera[2:], paquete.destino)
	binary.BigEndian.PutUint16(cabecera[4:], s.seqcounter)
	binary.BigEndian.PutUint16(cabecera[6:], paquete.long)
	s.seqcounter++
	log.Println(cabecera)
	log.Println(paquete.payload)
	_, err := s.port.Write(cabecera)
	if err != nil {
		log.Fatalf("Error al escribir cabecera en el puerto serie: %v", err)
		return err
	}
	_, err = s.port.Write(paquete.payload)
	if err != nil {
		log.Fatalf("Error al escribir payload en el puerto serie: %v", err)
		return err
	}
	return nil
}

func (s *SerialPort) cerrar() {
	s.flagCerrar = true
	s.port.Close()
}

func (s *SerialPort) iniciarRecibir(callback func(PaqueteFlow)) {

	s.flagCerrar = false
	for s.flagCerrar == false {
		buf := make([]byte, MAX_PACKET)
		n, err := s.port.Read(buf)
		if err != nil {
			if err != io.EOF {
				log.Println("Error leyendo del puerto serie: ", err)
			}
		} else {
			if n > 8 {
				buf = buf[:n]
				log.Println("", hex.EncodeToString(buf))

				var temperatura uint16
				var humedad uint16
				var luminosidad uint16
				var rssi uint16

				reader := bytes.NewReader(buf[8:12])
				err := binary.Read(reader, binary.BigEndian, &temperatura)
				if err != nil {
					log.Println("Error recibiendo datos: ", err)
				}
				reader = bytes.NewReader(buf[12:16])
				err = binary.Read(reader, binary.BigEndian, &humedad)
				if err != nil {
					log.Println("Error recibiendo datos: ", err)
				}
				reader = bytes.NewReader(buf[16:20])
				err = binary.Read(reader, binary.BigEndian, &luminosidad)
				if err != nil {
					log.Println("Error recibiendo datos: ", err)
				}
				reader = bytes.NewReader(buf[20:24])
				err = binary.Read(reader, binary.BigEndian, &rssi)
				if err != nil {
					fmt.Println("Error recibiendo datos: ", err)
				}

				recibido := PaqueteFlow{binary.BigEndian.Uint16(buf[0:2]), binary.BigEndian.Uint16(buf[2:4]), binary.BigEndian.Uint16(buf[4:6]), binary.BigEndian.Uint16(buf[6:8]), temperatura, humedad, luminosidad, rssi}
				callback(recibido)
			}
		}
	}
}

func paqueteRecibido(pkt PaqueteFlow) {
	log.Println("Paquete recibido!")
	log.Printf("Origen: %d; Destino: %d; Secuencia: %d; Longitud: %d; \n", pkt.origen, pkt.destino, pkt.seq, pkt.long)
	log.Printf("Datos:\n\tTemperatura: %f\n\tHumedad: %f\n\tLuminosidad: %f\n\tRSSI: %f", pkt.temperatura, pkt.humedad, pkt.luminosidad, pkt.rssi)

	var id uint16 = pkt.origen

	// Crear listas si no existen
	if temperaturas[id] == nil {
		temperaturas[id] = list.New()
		humedades[id] = list.New()
		luminosidades[id] = list.New()
		rssis[id] = list.New()
		ids[len(ids)] = id
		log.Println("Registrado nodo con id: ", id)
	}

	temperaturas[pkt.origen].PushFront(pkt.temperatura)
	humedades[pkt.origen].PushFront(pkt.humedad)
	luminosidades[pkt.origen].PushFront(pkt.luminosidad)
	rssis[pkt.origen].PushFront(pkt.rssi)
}

// Handlers HTTP
func handler_get(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token")
	w.Header().Set("Access-Control-Allow-Credentials", "true")

	var _destino int
	var _parametro string
	var err error
	if len(r.URL.Query()["id"]) > 0 {
		_destino, err = strconv.Atoi(r.URL.Query()["id"][0])
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			fmt.Fprintln(w, "Error del servidor:")
			fmt.Fprintln(w, err)
			return
		}
	} else {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintln(w, "Error en la consulta.")
		return
	}
	if len(r.URL.Query()["parametro"]) > 0 {
		_parametro = r.URL.Query()["parametro"][0]
	} else {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintln(w, "Error en la consulta.")
		return
	}
	// Crear paquete get y enviar a serial como MRP
	app.enviar('G', uint16(_destino), _parametro, "")
}
func handler_set(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token")
	w.Header().Set("Access-Control-Allow-Credentials", "true")

	var _destino int
	var _parametro, _valor string
	var err error
	if len(r.URL.Query()["id"]) > 0 {
		_destino, err = strconv.Atoi(r.URL.Query()["id"][0])
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			fmt.Fprintln(w, "Error del servidor:")
			fmt.Fprintln(w, err)
			return
		}
	} else {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintln(w, "Error en la consulta.")
		return
	}
	if len(r.URL.Query()["parametro"]) > 0 {
		_parametro = r.URL.Query()["parametro"][0]
	} else {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintln(w, "Error en la consulta.")
		return
	}
	if len(r.URL.Query()["valor"]) > 0 {
		_valor = r.URL.Query()["valor"][0]
	} else {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintln(w, "Error en la consulta.")
		return
	}

	// Crear paquete set y enviar a serial como MRP
	app.enviar('S', uint16(_destino), _parametro, _valor)
}

func handler_valor(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token")
	w.Header().Set("Access-Control-Allow-Credentials", "true")

	if (len(r.URL.Query()["id"]) == 0) || (len(r.URL.Query()["parametro"]) == 0) {
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte("Error en la consulta."))
		return
	}
	// Extraer id
	idc, _ := strconv.Atoi(r.URL.Query()["id"][0])
	id := uint16(idc)
	// Si no se ha registrado un nodo con ese id
	if temperaturas[id] == nil {
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte("Error en la consulta: no existe el nodo."))
	}
	// Buscar en map el parámetro pedido
	switch r.URL.Query()["parametro"][0] {
	case "temperatura":
		valor := (float64(temperaturas[id].Front().Value.(uint16))*0.01 - 40)
		w.Write([]byte(strconv.FormatFloat(valor, 'f', 3, 32)))
		log.Println("Consulta: Nodo ", id, ", temperatura: ", valor)
		break
	case "humedad":
		valor := (float64(humedades[id].Front().Value.(uint16)) / 65536.0 * 100)
		w.Write([]byte(strconv.FormatFloat(valor, 'f', 3, 32)))
		log.Println("Consulta: Nodo ", id, ", humedad: ", valor)
		break
	case "luminosidad":
		valor := (float64(luminosidades[id].Front().Value.(uint16)) / 65536.0 * 100)
		w.Write([]byte(strconv.FormatFloat(valor, 'f', 3, 32)))
		log.Println("Consulta: Nodo ", id, ", luminosidad: ", valor)
		break
	case "rssi":
		valor := rssis[id].Front().Value.(uint16)
		w.Write([]byte(strconv.Itoa(int(valor))))
		log.Println("Consulta: Nodo ", id, ", rssi: ", valor)
		break
	}
}

func handler_graficas(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token")
	w.Header().Set("Access-Control-Allow-Credentials", "true")

	if (len(r.URL.Query()["id"]) == 0) || (len(r.URL.Query()["parametro"]) == 0) {
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte("Error en la consulta."))
		return
	}
	// Extraer id
	idc, _ := strconv.Atoi(r.URL.Query()["id"][0])
	id := uint16(idc)
	// Si no se ha registrado un nodo con ese id
	if temperaturas[id] == nil {
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte("Error en la consulta: no existe el nodo."))
		return
	}

	// Gráficas
	parte1, err := ioutil.ReadFile("./graficas1.html")
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte("Error en la consulta: " + err.Error()))
		return
	}
	parte2, err := ioutil.ReadFile("./graficas2.html")
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte("Error en la consulta: " + err.Error()))
		return
	}

	// Parte 1
	b := bytes.NewBuffer(parte1)
	if _, err := b.WriteTo(w); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, "%s", err)
	}

	// Imprimir gráfica:

	// 	Buscar en map el parámetro pedido
	switch r.URL.Query()["parametro"][0] {
	case "temperatura":
		w.Write([]byte("document.getElementById('titulo').innerHTML='Temperatura: nodo " + r.URL.Query()["id"][0] + "';\n"))
		w.Write([]byte("var data = {labels: ["))
		contador := temperaturas[id].Len()
		for n := 0; n < contador; n++ {
			// Labels
			w.Write([]byte(strconv.Itoa(n)))
			if n != (contador - 1) {
				w.Write([]byte(","))
			}
		}
		w.Write([]byte("],\n datasets: [{data: ["))
		for e := temperaturas[id].Back(); e != nil; e = e.Prev() {
			valor := e.Value.(uint16)
			w.Write([]byte(strconv.Itoa(int(valor))))
			log.Println((strconv.Itoa(int(valor))))
			if e.Prev() != nil {
				w.Write([]byte(","))
			}
		}
		w.Write([]byte("], label: 'Temperatura',"))

		log.Println("Gráfica Temperatura: Nodo ", id)
		break
	case "humedad":
		w.Write([]byte("document.getElementById('titulo').innerHTML='Humedad: nodo " + r.URL.Query()["id"][0] + "';\n"))
		w.Write([]byte("var data = {datasets: [{data: ["))
		// Bucle
		contador := 0
		for e := humedades[id].Back(); e != nil; e = e.Prev() {
			valor := e.Value.(uint16)
			w.Write([]byte(strconv.Itoa(int(valor))))
			if e.Prev() != nil {
				w.Write([]byte(","))
			}
			contador++
		}
		w.Write([]byte("], label: 'Humedad'}],\nlabels: ["))

		for n := 0; n < contador; n++ {
			// Labels
			w.Write([]byte(strconv.Itoa(n)))
			if n != contador {
				w.Write([]byte(","))
			}
		}
		w.Write([]byte("],"))

		log.Println("Gráfica Humedad: Nodo ", id)
		break
	case "luminosidad":
		w.Write([]byte("document.getElementById('titulo').innerHTML='Luminosidad: nodo " + r.URL.Query()["id"][0] + "';\n"))
		w.Write([]byte("var data = {labels: ["))
		contador := luminosidades[id].Len()
		for n := 0; n < contador; n++ {
			// Labels
			w.Write([]byte(strconv.Itoa(n)))
			if n != (contador - 1) {
				w.Write([]byte(","))
			}
		}
		w.Write([]byte("],\n datasets: [{data: ["))
		// Bucle
		for e := luminosidades[id].Back(); e != nil; e = e.Prev() {
			valor := e.Value.(uint16)
			w.Write([]byte(strconv.Itoa(int(valor))))
			if e.Prev() != nil {
				w.Write([]byte(","))
			}
		}
		w.Write([]byte("], label: 'Luminosidad'}]]"))

		log.Println("Gráfica Luminosidad: Nodo ", id)
		break
	case "rssi":
		w.Write([]byte("document.getElementById('titulo').innerHTML='RSSI: nodo " + r.URL.Query()["id"][0] + "';\n"))
		w.Write([]byte("var data = {datasets: [{data: ["))
		// Bucle
		contador := 0
		for e := rssis[id].Back(); e != nil; e = e.Prev() {
			valor := e.Value.(uint16)
			w.Write([]byte(strconv.Itoa(int(valor))))
			if e.Prev() != nil {
				w.Write([]byte(","))
			}
			contador++
		}
		w.Write([]byte("], label: 'RSSI'}],\nlabels: ["))

		for n := 0; n < contador; n++ {
			// Labels
			w.Write([]byte(strconv.Itoa(n)))
			if n != contador {
				w.Write([]byte(","))
			}
		}
		w.Write([]byte("],"))

		log.Println("Gráfica RSSI: Nodo ", id)
		break
	}

	// Parte 2
	b = bytes.NewBuffer(parte2)
	if _, err := b.WriteTo(w); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, "%s", err)
	}
}

// Globales
var serie SerialPort
var app ProtocoloAPP

func main() {

	// Puerto serie
	//serie.inicializar(161, "COM3")
	//serie.iniciarRecibir(paqueteRecibido)
	//defer serie.cerrar()

	// Protocolo APP
	//app.attach(&serie)

	temperaturas[1] = list.New()
	var c uint16 = 0
	for c < 8 {
		temperaturas[1].PushBack(c * c * c)
		c++
	}
	temperaturas[1].PushBack(uint16(80))
	temperaturas[1].PushFront(uint16(60))

	// HTTP
	// Leer web de archivo
	http.Handle("/", http.FileServer(http.Dir("web")))
	//http.HandleFunc("/get", handler_get)
	//http.HandleFunc("/set", handler_set)
	http.HandleFunc("/valor", handler_valor)
	http.HandleFunc("/graficas", handler_graficas)
	http.ListenAndServe(":80", nil)

	// PRUEBAS
	// Enviar paquete
	/*pkt := Paquete{161, 162, 1, 5, nil}
	pkt.payload = []byte{'H', 'o', 'l', 'a', '!'}
	serie.enviar(pkt)*/

	/*// Write 4 bytes to the port.
	b := []byte{0x00, 0x01, 0x02, 0x03}
	n, err := port.Write(b)
	if err != nil {
		log.Fatalf("port.Write: %v", err)
	}

	log.Println("Wrote", n, "bytes.")*/

}

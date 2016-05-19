// SerialGateway project main.go
package main

import (
	"bytes"
	"container/list"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"io"
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
	temperatura float32
	humedad     float32
	luminosidad float32
	rssi        float32
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
		fmt.Println("Error enviando paquete de aplicación :", err)
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
	fmt.Println(cabecera)
	fmt.Println(paquete.payload)
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
				fmt.Println("Error reading from serial port: ", err)
			}
		} else {
			if n > 8 {
				buf = buf[:n]
				fmt.Println("", hex.EncodeToString(buf))

				var temperatura float32
				var humedad float32
				var luminosidad float32
				var rssi float32

				reader := bytes.NewReader(buf[8:12])
				err := binary.Read(reader, binary.BigEndian, &temperatura)
				if err != nil {
					fmt.Println("Error recibiendo datos: ", err)
				}
				reader = bytes.NewReader(buf[12:16])
				err = binary.Read(reader, binary.BigEndian, &humedad)
				if err != nil {
					fmt.Println("Error recibiendo datos: ", err)
				}
				reader = bytes.NewReader(buf[16:20])
				err = binary.Read(reader, binary.BigEndian, &luminosidad)
				if err != nil {
					fmt.Println("Error recibiendo datos: ", err)
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
	// TODO : Rellenar listas
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
		fmt.Fprintln(w, "Error en la consulta.")
		return
	}
	// Extraer id
	idc, _ := strconv.Atoi(r.URL.Query()["id"][0])
	id := uint16(idc)
	// Crear listas si no existen
	if temperaturas[id] == nil {
		temperaturas[id] = list.New()
		humedades[id] = list.New()
		luminosidades[id] = list.New()
		rssis[id] = list.New()
		ids[len(ids)] = id
		fmt.Println("Registrado nodo con id: ", id)
	}
	// Buscar en map el parámetro pedido
	switch r.URL.Query()["parametro"][0] {
	case "temperatura":
		w.Write([]byte(strconv.FormatFloat(temperaturas[id].Front().Value.(float64), 'f', 3, 32)))
		fmt.Fprintln(w, "Consulta: Nodo ", id, ", temperatura.")
		break
	case "humedad":
		w.Write([]byte(strconv.FormatFloat(humedades[id].Front().Value.(float64), 'f', 3, 32)))
		fmt.Fprintln(w, "Consulta: Nodo ", id, ", humedad.")
		break
	case "luminosidad":
		w.Write([]byte(strconv.FormatFloat(luminosidades[id].Front().Value.(float64), 'f', 3, 32)))
		fmt.Fprintln(w, "Consulta: Nodo ", id, ", luminosidad.")
		break
	case "rssi":
		w.Write([]byte(strconv.FormatFloat(rssis[id].Front().Value.(float64), 'f', 3, 32)))
		fmt.Fprintln(w, "Consulta: Nodo ", id, ", rssi.")
		break
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

	// HTTP
	// Leer web de archivo
	http.Handle("/", http.FileServer(http.Dir("/web")))
	//http.HandleFunc("/get", handler_get)
	//http.HandleFunc("/set", handler_set)
	http.HandleFunc("/valor", handler_valor)
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

	fmt.Println("Wrote", n, "bytes.")*/

}

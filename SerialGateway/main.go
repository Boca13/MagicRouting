// SerialGateway project main.go
package main

import (
	"encoding/hex"
	"fmt"
	"io"
	"log"
)

import "github.com/jacobsa/go-serial/serial"

const MAX_PACKET = 1500

func main() {
	fmt.Println("Hello World!")

	// Ejemplo
	// Set up options.
	options := serial.OpenOptions{
		PortName:        "COM4",
		BaudRate:        115200,
		DataBits:        8,
		StopBits:        1,
		MinimumReadSize: 1,
	}

	// Open the port.
	port, err := serial.Open(options)
	if err != nil {
		log.Fatalf("serial.Open: %v", err)
	}

	// Make sure to close it later.
	defer port.Close()

	// Write 4 bytes to the port.
	b := []byte{0x00, 0x01, 0x02, 0x03}
	n, err := port.Write(b)
	if err != nil {
		log.Fatalf("port.Write: %v", err)
	}

	fmt.Println("Wrote", n, "bytes.")

	for {
		buf := make([]byte, MAX_PACKET)
		n, err := port.Read(buf)
		if err != nil {
			if err != io.EOF {
				fmt.Println("Error reading from serial port: ", err)
			}
		} else {
			buf = buf[:n]
			fmt.Println("", hex.EncodeToString(buf))
		}
	}

}
